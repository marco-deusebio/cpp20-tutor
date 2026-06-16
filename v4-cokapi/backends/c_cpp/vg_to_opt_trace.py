# Convert a raw trace created by the Valgrind OPT C backend to a format
# that the OPT frontend can digest, making various optimizations and
# clean-ups along the way to beautify the trace

# Created 2015-10-04 by Philip Guo

# pass in full path name of a source file, which should end in '.c' or '.cpp'.
# assumes that the Valgrind-produced trace is $basename.vgtrace
# (without the '.c.' or '.cpp' extension)
#
# optionally, if you want to pass an error message to display at the end
# of the trace, pass it in via the --end-of-trace-error-msg argument


# this is pretty brittle and dependent on the user's gcc version and
# such because it generates code to conform to certain calling
# conventions, frame pointer settings (DON'T omit it!), etc., eeek
#
# we're assuming that the user has compiled with:
# gcc -ggdb -O0 -fno-omit-frame-pointer
#
# on a platform like:
'''
$ gcc -v
Using built-in specs.
COLLECT_GCC=gcc
COLLECT_LTO_WRAPPER=/usr/lib/gcc/x86_64-linux-gnu/4.8/lto-wrapper
Target: x86_64-linux-gnu
Configured with: ../src/configure -v --with-pkgversion='Ubuntu 4.8.4-2ubuntu1~14.04' --with-bugurl=file:///usr/share/doc/gcc-4.8/README.Bugs --enable-languages=c,c++,java,go,d,fortran,objc,obj-c++ --prefix=/usr --program-suffix=-4.8 --enable-shared --enable-linker-build-id --libexecdir=/usr/lib --without-included-gettext --enable-threads=posix --with-gxx-include-dir=/usr/include/c++/4.8 --libdir=/usr/lib --enable-nls --with-sysroot=/ --enable-clocale=gnu --enable-libstdcxx-debug --enable-libstdcxx-time=yes --enable-gnu-unique-object --disable-libmudflap --enable-plugin --with-system-zlib --disable-browser-plugin --enable-java-awt=gtk --enable-gtk-cairo --with-java-home=/usr/lib/jvm/java-1.5.0-gcj-4.8-amd64/jre --enable-java-home --with-jvm-root-dir=/usr/lib/jvm/java-1.5.0-gcj-4.8-amd64 --with-jvm-jar-dir=/usr/lib/jvm-exports/java-1.5.0-gcj-4.8-amd64 --with-arch-directory=amd64 --with-ecj-jar=/usr/share/java/eclipse-ecj.jar --enable-objc-gc --enable-multiarch --disable-werror --with-arch-32=i686 --with-abi=m64 --with-multilib-list=m32,m64,mx32 --with-tune=generic --enable-checking=release --build=x86_64-linux-gnu --host=x86_64-linux-gnu --target=x86_64-linux-gnu
Thread model: posix
gcc version 4.8.4 (Ubuntu 4.8.4-2ubuntu1~14.04)
'''


import json
import os
import pprint
import sys
from optparse import OptionParser

pp = pprint.PrettyPrinter(indent=2)

RECORD_SEP = '=== pg_trace_inst ==='


MAX_STEPS = 1000
ONLY_ONE_REC_PER_LINE = True

all_execution_points = []


def preserve_duplicate_json_keys(pairs):
    ret = {}
    seen = {}
    for key, val in pairs:
        count = seen.get(key, 0) + 1
        seen[key] = count
        if count > 1:
            key = key + '__dup' + str(count)
        ret[key] = val
    return ret


# False if record isn't parsed properly or is an exception
def process_record(lines):
    if not lines:
        return True # 'nil success case to keep the parser going

    err_lines = []
    stdout_lines = []
    regular_lines = []
    for e in lines:
        if e.startswith('ERROR: '):
            err_lines.append(e)
        elif e.startswith('STDOUT: '):
            stdout_lines.append(e)
        elif e.startswith('MAX_STEPS_EXCEEDED'):
            pass # oof
        else:
            regular_lines.append(e)

    rec = '\n'.join(regular_lines)
    try:
        # sometimes floating-point values print as:
        # "val":******
        # when they're weird values like overflow and NaN. in those
        # cases, replace with "val": null so as not to crash the json
        # parser
        rec = rec.replace('"val":******', '"val":null')
        obj = json.loads(rec, object_pairs_hook=preserve_duplicate_json_keys)
    except ValueError:
        print >> sys.stderr, "Ugh, bad record!", rec
        return False

    assert len(stdout_lines) == 1 # always have one!
    # it's encoded as JSON in a single line
    stdout_str = json.loads(stdout_lines[0][len('STDOUT: '):])

    # take the first error only
    err_str = err_lines[0] if err_lines else None

    x = process_json_obj(obj, err_str, stdout_str)
    all_execution_points.append(x)
    # it's a good idea to fail-fast on first exception since it's
    # pedagogically bad to keep executing despite errors
    if x['event'] == 'exception':
        return False
    return True


def process_json_obj(obj, err_str, stdout_str):
    #print '---'
    #pp.pprint(obj)
    #print

    assert len(obj['stack']) > 0 # C programs always have a main at least!
    obj['stack'].reverse() # make the stack grow down to follow convention
    top_stack_entry = obj['stack'][-1]

    # create an execution point object
    ret = {}

    heap = {}
    stack = []
    enc_globals = {}
    ret['heap'] = heap
    ret['stack_to_render'] = stack
    ret['globals'] = enc_globals

    # sometimes there are no globals in a trace
    if 'ordered_globals' in obj:
        ret['ordered_globals'] = obj['ordered_globals']
    else:
        ret['ordered_globals'] = []

    ret['line'] = obj['line']
    ret['func_name'] = top_stack_entry['func_name'] # use the 'topmost' entry's name

    if err_str:
        ret['event'] = 'exception'
        ret['exception_msg'] = err_str + '\n(Stopped running after the first error. Please fix your code.)'
    else:
        ret['event'] = 'step_line'

    ret['stdout'] = stdout_str

    if 'globals' in obj:
        for g_var, g_val in obj['globals'].iteritems():
            enc_globals[g_var] = encode_value(g_val, heap)

    for e in obj['stack']:
        stack_obj = {}
        stack.append(stack_obj)

        stack_obj['func_name'] = e['func_name']
        stack_obj['ordered_varnames'] = e['ordered_varnames']
        stack_obj['is_highlighted'] = e is top_stack_entry

        # hacky: does FP (the frame pointer) serve as a unique enough frame ID?
        # sometimes it's set to 0 :/
        stack_obj['frame_id'] = e['FP']

        stack_obj['unique_hash'] = stack_obj['func_name'] + '_' + stack_obj['frame_id']

        if 'line' in e:
            stack_obj['line'] = e['line']

        # unsupported
        stack_obj['is_parent'] = False
        stack_obj['is_zombie'] = False
        stack_obj['parent_frame_id_list'] = []

        enc_locals = {}
        stack_obj['encoded_locals'] = enc_locals

        for local_var, local_val in e['locals'].iteritems():
            enc_locals[local_var] = encode_value(local_val, heap)


    #pp.pprint(ret)
    #print [(e['func_name'], e['frame_id']) for e in ret['stack_to_render']]

    return ret


def get_std_string_pointer(obj):
    if obj.get('kind') != 'struct':
        return None

    type_name = obj.get('type') or ''
    if 'basic_string<char' not in type_name:
        return None

    members = obj.get('val') or {}
    dataplus = members.get('_M_dataplus')
    if not dataplus or dataplus.get('kind') != 'struct':
        return None

    dataplus_members = dataplus.get('val') or {}
    ptr = dataplus_members.get('_M_p')
    if ptr and ptr.get('kind') == 'pointer':
        return ptr

    return None


def parse_hex_ptr(val):
    if not isinstance(val, basestring):
        return None
    if not val.startswith('0x'):
        return None
    try:
        return int(val, 16)
    except ValueError:
        return None


def top_level_template_arg(type_name):
    start = type_name.find('vector<')
    if start < 0:
        return None
    start += len('vector<')
    depth = 0
    for i in range(start, len(type_name)):
        c = type_name[i]
        if c == '<':
            depth += 1
        elif c == '>':
            if depth == 0:
                return type_name[start:i].strip()
            depth -= 1
        elif c == ',' and depth == 0:
            return type_name[start:i].strip()
    return None


def top_level_template_args(type_name, template_name):
    start = type_name.find(template_name + '<')
    if start < 0:
        return None
    start += len(template_name) + 1
    args = []
    arg_start = start
    depth = 0
    for i in range(start, len(type_name)):
        c = type_name[i]
        if c == '<':
            depth += 1
        elif c == '>':
            if depth == 0:
                args.append(type_name[arg_start:i].strip())
                return args
            depth -= 1
        elif c == ',' and depth == 0:
            args.append(type_name[arg_start:i].strip())
            arg_start = i + 1
    return None


def display_cpp_type(type_name):
    normalized = (type_name or '').strip()
    if (normalized.startswith('std::__cxx11::basic_string<char') or
            normalized.startswith('std::basic_string<char') or
            normalized.startswith('basic_string<char')):
        return 'std::string'
    return normalized


def sizeof_cpp_type(type_name):
    normalized = (type_name or '').strip()
    if normalized in ('char', 'signed char', 'unsigned char', 'bool'):
        return 1
    if normalized in ('short', 'short int', 'unsigned short', 'unsigned short int'):
        return 2
    if normalized in ('int', 'unsigned int', 'float'):
        return 4
    if normalized in ('long', 'long int', 'unsigned long', 'unsigned long int',
                      'long long', 'long long int', 'unsigned long long',
                      'unsigned long long int', 'double'):
        return 8
    return None


def sizeof_trace_value(obj):
    addr = parse_hex_ptr(obj.get('addr'))
    if addr is None:
        return None

    if obj.get('kind') == 'base':
        return obj.get('size')

    if obj.get('kind') == 'pointer':
        return obj.get('size')

    if obj.get('kind') == 'struct':
        max_end = addr
        for member in (obj.get('val') or {}).values():
            member_addr = parse_hex_ptr(member.get('addr'))
            member_size = sizeof_trace_value(member)
            if member_addr is not None and member_size:
                max_end = max(max_end, member_addr + member_size)
        if max_end > addr:
            return max_end - addr

    if obj.get('kind') == 'array':
        elems = obj.get('val') or []
        if elems:
            last = elems[-1]
            last_addr = parse_hex_ptr(last.get('addr'))
            last_size = sizeof_trace_value(last)
            if last_addr is not None and last_size:
                return last_addr + last_size - addr

    return None


def infer_vector_element_size(deref_val):
    elems = deref_val.get('val') or []
    if len(elems) >= 2:
        first_addr = parse_hex_ptr(elems[0].get('addr'))
        second_addr = parse_hex_ptr(elems[1].get('addr'))
        if first_addr is not None and second_addr is not None and second_addr > first_addr:
            return second_addr - first_addr
    if elems:
        return sizeof_trace_value(elems[0])
    return None


def find_struct_member(obj, member_name):
    if obj.get('kind') != 'struct':
        return None

    members = obj.get('val') or {}
    if member_name in members:
        return members[member_name]

    for member in members.values():
        found = find_struct_member(member, member_name)
        if found is not None:
            return found

    return None


def get_struct_members_by_base_name(obj, member_name):
    if obj.get('kind') != 'struct':
        return []

    members = obj.get('val') or {}
    found = []
    for key, member in members.items():
        if key == member_name or key.startswith(member_name + '__dup'):
            found.append(member)

    found.sort(key=lambda member: parse_hex_ptr(member.get('addr')) or 0)
    return found


def get_std_array_summary(obj, heap):
    if obj.get('kind') != 'struct':
        return None

    type_name = obj.get('type') or ''
    if 'array<' not in type_name:
        return None

    members = obj.get('val') or {}
    elems = members.get('_M_elems')
    if not elems or elems.get('kind') != 'array':
        return None
    encoded_elems = encode_value(elems, heap)

    display_type = type_name
    if not display_type.startswith('std::'):
        display_type = 'std::' + display_type

    return [
        'C_STRUCT',
        obj['addr'],
        display_type,
        ['size', ['C_DATA', obj['addr'], 'size_t', len(encoded_elems) - 2]],
        ['elements', encoded_elems]
    ]


def get_std_unique_ptr_summary(obj, heap):
    if obj.get('kind') != 'struct':
        return None

    type_name = obj.get('type') or ''
    if 'unique_ptr<' not in type_name:
        return None

    ptr = find_struct_member(obj, '_M_head_impl')
    if not ptr or ptr.get('kind') != 'pointer':
        return None

    args = top_level_template_args(type_name, 'unique_ptr') or ['element']
    display_type = 'std::unique_ptr<' + display_cpp_type(args[0]) + '>'
    ret = [
        'C_STRUCT',
        obj['addr'],
        display_type,
        ['pointer', encode_value(ptr, heap)]
    ]

    deref_val = ptr.get('deref_val')
    if deref_val and deref_val.get('kind') == 'heap_block':
        vals = deref_val.get('val') or []
        if vals:
            ret.append(['pointee', encode_value(vals[0], heap)])

    return ret


def get_std_tuple_summary(obj, heap):
    if obj.get('kind') != 'struct':
        return None

    type_name = obj.get('type') or ''
    if 'tuple<' not in type_name:
        return None

    elements = get_struct_members_by_base_name(obj, '_M_head_impl')
    if not elements:
        return None

    args = top_level_template_args(type_name, 'tuple') or []
    display_args = [display_cpp_type(arg) for arg in args]
    if display_args:
        display_type = 'std::tuple<' + ', '.join(display_args) + '>'
    else:
        display_type = 'std::tuple'

    ret = [
        'C_STRUCT',
        obj['addr'],
        display_type,
        ['size', ['C_DATA', obj['addr'], 'size_t', len(elements)]]
    ]

    # libstdc++ stores tuple leaves in reverse source-element order.
    for idx, element in enumerate(reversed(elements)):
        ret.append([str(idx), encode_value(element, heap)])

    return ret


def get_std_pair_summary(obj, heap):
    if obj.get('kind') != 'struct':
        return None

    type_name = obj.get('type') or ''
    if 'pair<' not in type_name:
        return None

    members = obj.get('val') or {}
    first = members.get('first')
    second = members.get('second')
    if first is None or second is None:
        return None

    args = top_level_template_args(type_name, 'pair') or ['first', 'second']
    if len(args) >= 2:
        display_type = 'std::pair<' + display_cpp_type(args[0]) + ', ' + display_cpp_type(args[1]) + '>'
    else:
        display_type = 'std::pair'

    return [
        'C_STRUCT',
        obj['addr'],
        display_type,
        ['first', encode_value(first, heap)],
        ['second', encode_value(second, heap)]
    ]


def get_std_vector_summary(obj, heap):
    if obj.get('kind') != 'struct':
        return None

    type_name = obj.get('type') or ''
    if 'vector<' not in type_name:
        return None

    members = obj.get('val') or {}
    impl = members.get('_M_impl')
    if not impl or impl.get('kind') != 'struct':
        return None

    impl_members = impl.get('val') or {}
    start = impl_members.get('_M_start')
    finish = impl_members.get('_M_finish')
    end = impl_members.get('_M_end_of_storage')
    if not start or not finish or not end:
        return None
    if start.get('kind') != 'pointer' or finish.get('kind') != 'pointer' or end.get('kind') != 'pointer':
        return None

    elem_type = top_level_template_arg(type_name) or 'element'
    elem_display_type = display_cpp_type(elem_type)
    elem_size = sizeof_cpp_type(elem_type)
    deref_val = start.get('deref_val')
    if not elem_size and deref_val and deref_val.get('kind') == 'heap_block':
        elem_size = infer_vector_element_size(deref_val)
    start_addr = parse_hex_ptr(start.get('val'))
    finish_addr = parse_hex_ptr(finish.get('val'))
    end_addr = parse_hex_ptr(end.get('val'))
    size = '<UNINITIALIZED>'
    capacity = '<UNINITIALIZED>'
    if elem_size and start_addr is not None and finish_addr is not None and finish_addr >= start_addr:
        size = (finish_addr - start_addr) // elem_size
    if elem_size and start_addr is not None and end_addr is not None and end_addr >= start_addr:
        capacity = (end_addr - start_addr) // elem_size

    ret = [
        'C_STRUCT',
        obj['addr'],
        'std::vector<' + elem_display_type + '>',
        ['size', ['C_DATA', finish['addr'], 'size_t', size]],
        ['capacity', ['C_DATA', end['addr'], 'size_t', capacity]],
        ['data', ['C_DATA', start['addr'], 'pointer', start.get('val')]]
    ]

    if isinstance(size, (int, long)) and deref_val and deref_val.get('kind') == 'heap_block':
        elements = ['C_ARRAY', deref_val['addr']]
        for element in (deref_val.get('val') or [])[:size]:
            elements.append(encode_value(element, heap))
        ret.append(['elements', elements])

    return ret


# returns an encoded value in OPT format and possibly mutates the heap
def encode_value(obj, heap):
    if obj['kind'] == 'base':
        return ['C_DATA', obj['addr'], obj['type'], obj['val']]

    elif obj['kind'] == 'pointer':
        if 'deref_val' in obj:
            encode_value(obj['deref_val'], heap) # update the heap
        return ['C_DATA', obj['addr'], 'pointer', obj['val']]

    elif obj['kind'] == 'struct':
        std_string_ptr = get_std_string_pointer(obj)
        if std_string_ptr is not None:
            if 'deref_val' in std_string_ptr:
                encode_value(std_string_ptr['deref_val'], heap)
            return ['C_DATA', obj['addr'], 'std::string', std_string_ptr['val']]

        std_array_summary = get_std_array_summary(obj, heap)
        if std_array_summary is not None:
            return std_array_summary

        std_unique_ptr_summary = get_std_unique_ptr_summary(obj, heap)
        if std_unique_ptr_summary is not None:
            return std_unique_ptr_summary

        std_tuple_summary = get_std_tuple_summary(obj, heap)
        if std_tuple_summary is not None:
            return std_tuple_summary

        std_pair_summary = get_std_pair_summary(obj, heap)
        if std_pair_summary is not None:
            return std_pair_summary

        std_vector_summary = get_std_vector_summary(obj, heap)
        if std_vector_summary is not None:
            return std_vector_summary

        ret = ['C_STRUCT', obj['addr'], obj['type']]

        # sort struct members by address so that they look ORDERED
        members = obj['val'].items()
        members.sort(key=lambda e: e[1]['addr'])
        for k, v in members:
            entry = [k, encode_value(v, heap)] # TODO: is an infinite loop possible here?
            ret.append(entry)
        return ret

    elif obj['kind'] == 'array':
        # backwards compatibility for old 1-D array format:
        if 'dimensions' not in obj or len(obj['dimensions']) < 2:
            ret = ['C_ARRAY', obj['addr']]
            for e in obj['val']:
                ret.append(encode_value(e, heap)) # TODO: is an infinite loop possible here?
            return ret
        else:
            # put dimensions as the 3rd element:
            ret = ['C_MULTIDIMENSIONAL_ARRAY', obj['addr'], obj['dimensions']]
            for e in obj['val']:
                ret.append(encode_value(e, heap)) # TODO: is an infinite loop possible here?
            return ret

    elif obj['kind'] == 'typedef':
        # pass on the typedef type name into obj['val'], then recurse
        obj['val']['type'] = obj['type']
        return encode_value(obj['val'], heap)

    elif obj['kind'] == 'heap_block':
        new_elt = ['C_ARRAY', obj['addr']]
        for e in obj['val']:
            new_elt.append(encode_value(e, heap)) # TODO: is an infinite loop possible here?
        heap[obj['addr']] = new_elt
        # TODO: what about heap-to-heap pointers?

    else:
        assert False


if __name__ == '__main__':
    parser = OptionParser(usage="Create an OPT trace from a Valgrind trace")
    parser.add_option("--create_jsvar", dest="js_varname", default=None,
                      help="Create a JavaScript variable out of the trace")
    parser.add_option("--jsondump", dest="jsondump", action="store_true", default=False,
                      help="Dump compact JSON as output")
    parser.add_option("--prettydump", dest="prettydump", action="store_true", default=False,
                      help="Dump pretty-printed JSON as output")
    parser.add_option("--end-of-trace-error-msg", dest="end_of_trace_error_msg", default=None,
                      help="Display this error message at the end of the trace")

    (options, args) = parser.parse_args()

    fn = args[0]
    basename, ext = os.path.splitext(fn)
    assert ext in ('.c', '.cpp')
    cur_record_lines = []

    success = True

    for line in open(basename + '.vgtrace'):
        line = line.strip()
        if line == RECORD_SEP:
            success = process_record(cur_record_lines)
            if not success:
                break
            cur_record_lines = []
        else:
            cur_record_lines.append(line)

    # only parse final record if we've been successful so far; i.e., die
    # on the first failed parse
    if success:
        success = process_record(cur_record_lines)

    # now do some filtering action based on heuristics
    filtered_execution_points = []

    for pt in all_execution_points:
        # any execution point with a 0x0 frame pointer is bogus
        frame_ids = [e['frame_id'] for e in pt['stack_to_render']]
        func_names = [e['func_name'] for e in pt['stack_to_render']]
        if '0x0' in frame_ids:
            continue

        # any point with DUPLICATE frame_ids is bogus, since it means
        # that the frame_id of some frame hasn't yet been updated
        if len(set(frame_ids)) < len(frame_ids):
            continue

        # any point with a weird '???' function name is bogus
        # but we shouldn't have any more by now
        #assert '???' not in func_names # actually nevermind on this for now - we still sometimes get '???' so just skip those
        if '???' in func_names:
            continue

        #print func_names, frame_ids
        filtered_execution_points.append(pt)


    final_execution_points = []
    if filtered_execution_points:
        final_execution_points.append(filtered_execution_points[0])
        # finally, make sure that each successive entry contains
        # frame_ids that are either identical to the previous one, or
        # differ by the addition or subtraction of one element at the
        # end, which represents a function call or return, respectively.
        # there are weird cases like:
        #
        # [u'main'] [u'0xFFEFFFE30']
        # [u'main'] [u'0xFFEFFFE30']
        # [u'foo'] [u'0xFFEFFFDC0'] <- bogus
        # [u'main', u'foo'] [u'0xFFEFFFE30', u'0xFFEFFFDC0']
        # [u'main', u'foo'] [u'0xFFEFFFE30', u'0xFFEFFFDC0']
        #
        # where the middle entry should be FILTERED OUT since it's
        # missing 'main' for some reason
        for prev, cur in zip(filtered_execution_points, filtered_execution_points[1:]):
            prev_frame_ids = [e['frame_id'] for e in prev['stack_to_render']]
            cur_frame_ids = [e['frame_id'] for e in cur['stack_to_render']]

            # identical, we're good to go
            if prev_frame_ids == cur_frame_ids:
                final_execution_points.append(cur)
            elif len(prev_frame_ids) < len(cur_frame_ids):
                # cur_frame_ids is prev_frame_ids + 1 extra element on
                # the end -> function call
                if prev_frame_ids == cur_frame_ids[:-1]:
                    final_execution_points.append(cur)
            elif len(prev_frame_ids) > len(cur_frame_ids):
                # cur_frame_ids is prev_frame_ids MINUS the last element on
                # the end -> function return
                if cur_frame_ids == prev_frame_ids[:-1]:
                    final_execution_points.append(cur)

        assert len(final_execution_points) <= len(filtered_execution_points)

        cur_ind = 1
        # now mark 'call' and' 'return' events via the same heuristic as above
        for prev, cur in zip(final_execution_points, final_execution_points[1:]):
            prev_frame_ids = [e['frame_id'] for e in prev['stack_to_render']]
            cur_frame_ids = [e['frame_id'] for e in cur['stack_to_render']]

            if len(prev_frame_ids) < len(cur_frame_ids):
                if prev_frame_ids == cur_frame_ids[:-1]:
                    cur['event'] = 'call'
                # optimization -- when you find a 'call' instruction,
                # look ahead in the trace to find all *consecutive*
                # entries with the same frame_ids and on the same line,
                # then eliminate those from the trace.
                #
                # if we don't do this optimization, then the visualizer
                # will show multiple steps for entering a function call,
                # with formal parameters being filled in with their
                # values along the way; while this is somewhat
                # informative, it's also kinda extraneous. instead, we
                # want to skip over all parameter initialization and
                # jump right into the function body right away with all
                # the parameters initialized
                lookahead = final_execution_points[cur_ind+1:] # start at the next index
                for future_step in lookahead:
                    future_frame_ids = [e['frame_id'] for e in future_step['stack_to_render']]
                    if cur_frame_ids == future_frame_ids and cur['line'] == future_step['line']:
                        future_step['to_delete'] = True
                    else:
                        # BREAK AS SOON AS you change lines or stack
                        # frame_id contents, since we don't want to be
                        # over-eager and cut out *non-consecutive*
                        # elements from the trace
                        break
            elif len(prev_frame_ids) > len(cur_frame_ids):
                if cur_frame_ids == prev_frame_ids[:-1]:
                    prev['event'] = 'return'
            cur_ind += 1 # tricky indent

        # make the last statement a faux 'return', presumably from main
        if success:
            if options.end_of_trace_error_msg:
                # make last statement an exception if end_of_trace_error_msg passed in
                final_execution_points[-1]['event'] = 'exception'
                final_execution_points[-1]['exception_msg'] = options.end_of_trace_error_msg
            else:
                # make last statement a faux 'return', presumably from main
                final_execution_points[-1]['event'] = 'return'


    # kludgy: don't do to_delete for return events, since if we do this,
    # then we may be skipping return events for one-liner functions like
    #   int getInt() { return static_const_member;}
    # due to our above optimization to cut out all events on the same
    # line as a 'call' instruction. in a one-liner function, the call
    # and return are on the same line, so we don't want to delete the return
    for e in final_execution_points:
        if e['event'] == 'return':
            if 'to_delete' in e:
                del e['to_delete']


    # only keep the FIRST 'step_line' event for any given line, to match what
    # a line-level debugger would do
    # (try to do this before other optimizations)
    if ONLY_ONE_REC_PER_LINE:
        tmp = []
        prev_event = None
        prev_line = None
        prev_frame_ids = None

        for elt in final_execution_points:
            skip = False
            cur_event = elt['event']
            cur_line = elt['line']
            cur_frame_ids = [e['frame_id'] for e in elt['stack_to_render']]
            if prev_frame_ids:
                if cur_event == prev_event == 'step_line':
                    if cur_line == prev_line and cur_frame_ids == prev_frame_ids:
                        skip = True

            if not skip:
                tmp.append(elt)

            prev_event = cur_event
            prev_line = cur_line
            prev_frame_ids = cur_frame_ids

        final_execution_points = tmp # the ole' switcheroo

    # optimization: if we're returning to the SAME LINE in the
    # caller as it originally called this function with, then
    # skip this step since it's redundant. for example:
    '''
void* foo() {
void *x = malloc(1);
return x;
}
int main() {
void *x = foo(); // <-- there is an extraneous step here AFTER foo returns but
             //     before its return value is assigned to x. this optimization
             //     eliminates this step to clean up the trace a bit
}
    '''
    for prev, cur, next in zip(final_execution_points, final_execution_points[1:], final_execution_points[2:]):
        if prev['event'] == 'return' and len(prev['stack_to_render']) > 1:
            prev_caller = prev['stack_to_render'][-2]
            cur_top = cur['stack_to_render'][-1]
            # one additional subtle caveat is that we should delete only
            # if cur['func_name'] == next['func_name'] because otherwise
            # we will be directly jumping into another function without
            # first showing the return to cur, which may look JARRING
            if (cur_top['frame_id'] == prev_caller['frame_id']) and \
               (cur_top['line'] == prev_caller['line']) and \
               (cur['func_name'] == next['func_name']):
                cur['to_delete'] = True


    # now eliminate all steps before the first call to 'main' to clean up the trace,
    # especially for C++ code with weird pre-main initializers
    for e in final_execution_points:
        if e['func_name'] == 'main':
            break # GET OUT!
        else:
            e['to_delete'] = True


    final_execution_points = [e for e in final_execution_points if 'to_delete' not in e]


    if len(final_execution_points) > MAX_STEPS:
      # truncate to MAX_STEPS entries
        final_execution_points = final_execution_points[:MAX_STEPS]
        final_execution_points[-1]['event'] = 'instruction_limit_reached'
        final_execution_points[-1]['exception_msg'] = 'Stopped after running ' + str(MAX_STEPS) + ' steps. Please shorten your code,\nsince Python Tutor is not designed to handle long-running code.'


    cod = open(fn).read()
    # produce the final trace, voila!
    final_res = {'code': cod, 'trace': final_execution_points}

    # use sort_keys to get some sensible ordering on object keys
    if options.js_varname:
        s = json.dumps(final_res, indent=2, sort_keys=True)
        print 'var ' + options.js_varname + ' = ' + s + ';'
    elif options.jsondump:
        print json.dumps(final_res, sort_keys=True)
    elif options.prettydump:
        print json.dumps(final_res, indent=2, sort_keys=True)
    else:
        assert False
