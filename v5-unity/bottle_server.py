from bottle import route, request, response, run, static_file
from io import StringIO
import json
import os
import urllib.request
import urllib.error
import pg_logger

@route('/web_exec_.py')
@route('/LIVE_exec_.py')
@route('/viz_interaction.py')
@route('/syntax_err_survey.py')
@route('/runtime_err_survey.py')
@route('/eureka_survey.py')
@route('/error_log.py')
def dummy_ok(name=None):
    return 'OK'

@route('/web_exec_py2.py')
@route('/web_exec_py3.py')
@route('/LIVE_exec_py2.py')
@route('/LIVE_exec_py3.py')
def get_py_exec():
    out_s = StringIO()

    def json_finalizer(input_code, output_trace):
        ret = dict(code=input_code, trace=output_trace)
        out_s.write(json.dumps(ret, indent=None))

    options = json.loads(request.query.options_json)
    pg_logger.exec_script_str_local(
        request.query.user_script,
        request.query.raw_input_json,
        options['cumulative_mode'],
        options['heap_primitives'],
        json_finalizer
    )

    response.content_type = 'application/json'
    return out_s.getvalue()

def proxy_to_local_cokapi(endpoint):
    query = request.query_string
    local_url = 'http://localhost:3000/' + endpoint
    if query:
        local_url += '?' + query

    try:
        req = urllib.request.Request(
            local_url,
            headers={
                'User-Agent': 'cpp-tutor-local-only',
                'Accept': 'application/json,text/plain,*/*'
            }
        )
        with urllib.request.urlopen(req, timeout=45) as remote:
            response.status = remote.status
            response.content_type = remote.headers.get('Content-Type', 'application/json')
            return remote.read()

    except Exception as e:
        response.status = 502
        response.content_type = 'text/plain'
        return 'Local cpp-tutor backend error: ' + repr(e)

@route('/web_exec_cpp.py')
@route('/LIVE_exec_cpp.py')
def local_cpp_exec():
    return proxy_to_local_cokapi('exec_cpp')

@route('/web_exec_c.py')
@route('/LIVE_exec_c.py')
def local_c_exec():
    return proxy_to_local_cokapi('exec_c')

@route('/')
def index_root():
    return static_file('visualize.html', root='.')

@route('/<filepath:path>')
def server_static(filepath):
    return static_file(filepath, root='.')

if __name__ == "__main__":
    run(host='localhost', port=5000, reloader=False)
