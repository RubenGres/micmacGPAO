from pathlib import Path
import argparse
import sys
import os
import requests
import json
import time
import glob
import numpy as np
import pickle
from datetime import datetime
from difflib import SequenceMatcher

from gpao.builder import Builder
from gpao.project import Project
from gpao.job import Job


def arg_parser():
    """ Extraction des arguments de la ligne de commande """
    parser = argparse.ArgumentParser()

    parser.add_argument(
        'target',
        nargs='?',
        default=None,
        help="Target for the makefile"
    )

    parser.add_argument(
        '--file',
        '-f',
        type=str,
        help="Makefile"
    )

    parser.add_argument(
        '--JSON',
        nargs="?",
        const='./',
        type=str,
        help="Path where to save the json file to. If not specified the project will not be save as json. Default : project.json"
    )

    parser.add_argument(
        '--project_name',
        nargs="?",
        const='makefile_gpao_project',
        type=str,
        help="Name of the associated project in GPAO"
    )

    parser.add_argument(
        '--PPID',
        nargs="?",
        const='0000',
        type=str,
        help="PID of the process calling makeGPAO"
    )
    
    parser.add_argument(
        '--API',
        action='store_true',
        help="If set, will send the project directly to the API"
    )

    parser.add_argument(
        '--API_URL',
        nargs="?",
        const='localhost',
        type=str,
        help="URL of the GPAO API"
    )

    parser.add_argument(
        '--API_PROTOCOL',
        nargs="?",
        const='http',
        type=str,
        help="Protocol of the GPAO API"
    )

    parser.add_argument(
        '--API_PORT',
        nargs="?",
        const='8080',
        type=str,
        help="Port of the GPAO API"
    )

    parser.add_argument(
        '--await',
        dest='wait',
        action='store_true',
        help='Wait for all the jobs to be finished in GPAO (only if using the --API tag)'
    )

    parser.add_argument(
        '--wd',
        nargs="?",
        dest='working_dir',
        const=None,
        type=str,
        help="base working directory for the command (user defined)"
    )

    parser.add_argument(
        '--userdir',
        dest='user_dir',
        type=str,
        help="absolute path of the user directory from where the command is called"
    )

    parser.add_argument(
        '--conda_env',
        nargs="?",
        dest='conda_env',
        const=None,
        type=str,
        help="conda virtual env name"
    )

    return parser.parse_known_args()

def reconstruct_url(abs_path, cwd_path):
    match = SequenceMatcher(None, abs_path, cwd_path).find_longest_match()
    return cwd_path + abs_path[match.a + match.size:]

def prefix_command(command, working_dir, user_dir, conda_env):
    fixed_dir = working_dir

    if user_dir:
        fixed_dir = reconstruct_url(user_dir, working_dir)
    
    cmd = f'cd {fixed_dir} && {command}'

    if conda_env:
        cmd = f'source ~/.bashrc && conda activate {conda_env} && {cmd}'

    cmd = cmd.replace('"', '\\"')
    cmd = f'bash -c "{cmd}"'

    return cmd

def make_absolute(command):
    # Split the string into a list of substrings separated by spaces
    substrings = command.split()

    # Iterate over the substrings and check if they are relative paths
    for i, substring in enumerate(substrings):
        if substring == '.' or substring.startswith("./") or substring.startswith("../") or ("=./" in substring):
            if "=." in substring:
                key, value = substring.split('=')
                absolute_path = f"{key}={os.path.abspath(value)}"
            else:
                absolute_path = os.path.abspath(substring)
            
            # Replace the substring with the absolute path
            substrings[i] = absolute_path

    # Join the substrings back into a single string
    return " ".join(substrings)


def parse_makefile(makefile_path):
    with open(makefile_path) as f:
        lines = f.readlines()

    result_dict = {}
    current_key = None
    for line in lines:        
        # if line is empty, continue
        if not line.strip():
            continue

        if line.startswith('\t'):
            if current_key is None:
                raise ValueError('File format is invalid')
            result_dict[current_key]['cmd'] = line.strip()
        elif ':' in line:
                current_key, deps = line.split(':')
                current_key = current_key.strip()
                result_dict[current_key] = dict(deps=deps.strip().split(), cmd='true')
        else:
            raise ValueError('File format is invalid')

    return result_dict


# create the project from a makefile_dict and a target recursively, this hurt my brain to make
def create_project(makefile_path, target, project_name, working_dir=None, conda_env=None, user_dir=None):

    makefile_dict = parse_makefile(makefile_path)
    jobs = {}

    def build_proj_rec(target):
        dependencies = makefile_dict[target]['deps']
        
        for dependency in dependencies:
            if dependency not in jobs.keys():
                new_jobs = build_proj_rec(dependency)
                jobs.update(new_jobs)
        
        #cmd = make_absolute(makefile_dict[target]['cmd'])
        cmd = makefile_dict[target]['cmd']

        if working_dir:
            cmd = prefix_command(cmd, working_dir, user_dir, conda_env)

        deps = [jobs[k] for k in dependencies]

        if (target != "all"):
            job = Job(target, cmd, deps)
            jobs[target] = job

        return jobs

    project_jobs = build_proj_rec(target).values()

    if len(project_jobs) == 0:
        return None

    return Project(project_name, project_jobs)


def save_as_json(ARGS, project):
    json_path = f"{ARGS.JSON}/MM3D_{ARGS.PPID}.json"
    pickle_path = f"{ARGS.JSON}/MM3D_{ARGS.PPID}.pickle"

    # check if builder JSON exists
    if os.path.exists(json_path):
        # open the last builder pickle file
        with open(pickle_path, "rb") as f:
            projects = pickle.load(f)

        # add dependencies
        for i, p in enumerate(projects):
            project.add_dependency({"id": i})

        projects.append(project)
    else:
        projects = [project]

    # save the project as a pickle file
    with open(pickle_path, "wb") as f:
        pickle.dump(projects, f)

    # save/override GPAO JSON file
    builder = Builder(projects)
    builder.save_as_json(json_path)


def wait_for_project(project_name, URL_API):
    project_done = False

    while not project_done:
        response = requests.get(f"{URL_API}/api/projects")

        data = json.loads(response.text)
        filtered_data = [project for project in data if project['name'].startswith(project_name)]

        if len(filtered_data) == 0:
            # no project containing this name
            continue

        elif len(filtered_data) == 1:
            project = filtered_data[0]

        else:
            def get_key(i, filtered_data):
                split_name = filtered_data[i]['name'].split('_')
                if len(split_name) > 1 and split_name[-1].isnumeric():
                    return int(split_name[-1])
                else:
                    return -1

            max_index = max(range(len(filtered_data)), key=lambda i: get_key(i, filtered_data))
            project = filtered_data[max_index]
        
        if project['status'] == 'failed':
            raise RuntimeError('project failed, more info can be found in the GPAO monitor')
        
        project_done = project['status'] == 'done'
        if not project_done:
            time.sleep(0.1)

    return 0
    

def send_to_api(ARGS, project):
    builder = Builder([project])

    URL_API = f"{ARGS.API_PROTOCOL}://{ARGS.API_URL}:{ARGS.API_PORT}"

    builder.send_project_to_api(URL_API)
    
    if ARGS.wait:
        wait_for_project(project.get_name(), URL_API)
        

def main():
    ARGS, unknown_ARGS = arg_parser()

    makefile_path = ARGS.file
    if not ARGS.file:
        filenames = ["GNUmakefile", "makefile", "Makefile"]

        for filename in filenames:
            if os.path.exists(filename):
                makefile_path = filename
                break

    if(not makefile_path):
       sys.exit("ERROR: no makefile provided. Use --help to get help on the command")
    
    target = ARGS.target or "all"
    project = create_project(makefile_path, target, ARGS.project_name, working_dir=ARGS.working_dir, conda_env=ARGS.conda_env, user_dir=ARGS.user_dir)

    if project is not None:
        if ARGS.JSON:
            save_as_json(ARGS, project)

        if ARGS.API:
            print(f"MM_GPAO: sending {len(project.jobs)} jobs to the GPAO... (project: {ARGS.project_name})")
            send_to_api(ARGS, project)
    else:
        print("No job in the current makefile, nothing was sent to GPAO.")

    exit(0)


if __name__ == "__main__" :
    main()
