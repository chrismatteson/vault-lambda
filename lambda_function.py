import json
import shutil
import time
import os
import subprocess
import boto3
import urlparse
from botocore.vendored import requests
s3 = boto3.resource('s3')
from tempfile import mkstemp
from os import fdopen, remove
from shutil import move

LAMBDA_TASK_ROOT = os.environ.get('LAMBDA_TASK_ROOT', os.path.dirname(os.path.abspath(__file__)))
CURR_BIN_DIR = os.path.join(LAMBDA_TASK_ROOT, 'bin')
BUCKET_NAME = os.environ.get('BUCKET_NAME')
KEY_ID = os.environ.get('KEY_ID')
LIB_DIR = os.path.join(LAMBDA_TASK_ROOT, 'lib')
### In order to get permissions right, we have to copy them to /tmp
BIN_DIR = '/tmp/bin'

def replace(file_path, pattern, subst):
    #Create temp file
    fh, abs_path = mkstemp()
    with fdopen(fh,'w') as new_file:
        with open(file_path) as old_file:
            for line in old_file:
                new_file.write(line.replace(pattern, subst))
    #Remove original file
    remove(file_path)
    #Move new file
    move(abs_path, file_path)

# This is necessary as we don't have permissions in /var/tasks/bin where the lambda function is running
def _init_bin(executable_name):
    start = time.clock()
    if not os.path.exists(BIN_DIR):
        print("Creating bin folder")
        os.makedirs(BIN_DIR)
    print("Copying binaries for "+executable_name+" in /tmp/bin")
    newfile  = os.path.join(BIN_DIR, executable_name)
    s3.Bucket(BUCKET_NAME).download_file(executable_name, newfile)
    print("Giving new binaries permissions for lambda")
    os.chmod(newfile, 0775)
    elapsed = (time.clock() - start)
    print(executable_name+" ready in "+str(elapsed)+'s.')
    
def remove_prefix(s):
    prefix = s.split('/')[1]
    print(prefix)
    return s[len(prefix)+1:]

def lambda_handler(event, context):
    _init_bin('vault')
    s='-config='
    s+=os.path.join(BIN_DIR, 'vault.hcl')
    cmdline = [os.path.join(BIN_DIR, 'vault'), 'server', s]
#    cmdline = [os.path.join(BIN_DIR, 'vault'), 'server', '-dev']
#    try:
#        print subprocess.check_output(cmdline, shell=False, stderr=subprocess.STDOUT)
#    except subprocess.CalledProcessError, e:
#        print "Ping stdout output:\n", e.output
    shutil.copy(os.path.join(LAMBDA_TASK_ROOT, 'vault.hcl'), os.path.join(BIN_DIR, 'vault.hcl'))
    replace(os.path.join(BIN_DIR, 'vault.hcl'), 'BUCKET_NAME', BUCKET_NAME)
    replace(os.path.join(BIN_DIR, 'vault.hcl'), 'KEY_ID', KEY_ID)
    subprocess.Popen(cmdline, shell=False, stderr=subprocess.STDOUT)
    print('subprocess started')
    while True:
        try:
            response = requests.get('http://localhost:8200/v1/sys/seal-status')
            print('vault is running!')
            break
        except requests.ConnectionError:
            print('sleeping')
            time.sleep(5.0)
    path = remove_prefix(event['path'])
    print(path)
    url=urlparse.urljoin('http://localhost:8200', path)
    if event['httpMethod'] == 'GET':
        request = requests.get(url, headers=event['headers'])
    elif event['httpMethod'] == 'PUT':
        print event['body']
        request = requests.put(url, headers=event['headers'], data=event['body'])
    elif event['httpMethod'] == 'POST':
        print event['body']
        request = requests.post(url, headers=event['headers'], data=event['body'])
    else:
        print(fail)
    print(request.text)
    if request.text:
        data = request.json()
        print(data)
        return {
            'statusCode': request.status_code,
            'body': json.dumps(data),
            'isBase64Encoded': 'false'
        }
    else:
        print('empty')
        return {
            'statusCode': request.status_code,
            'isBase64Encoded': 'false'
        }
