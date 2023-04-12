from pathlib import Path
import argparse
import sys
import os
import time
import glob
import numpy as np
import pickle
from datetime import datetime

from gpao.builder import Builder
from gpao.project import Project
from gpao.job import Job


def arg_parser():
    """ Extraction des arguments de la ligne de commande """
    parser = argparse.ArgumentParser()

    parser.add_argument(
        'makefile',
        nargs='?',
        default=None,
        help="Makefile"
    )

    #TODO change to target
    parser.add_argument(
        'target',
        type=str,
        help="Target for the makefile"
    )

    parser.add_argument(
        '--file',
        '-f',
        type=str,
        help="Makefile"
    )

    parser.add_argument(
        '--jobs',
        '-j',
        metavar='N',
        type=int,
        help='An integer for the number of jobs'
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
        const='MicMac_project',
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
        nargs="?",
        const='localhost',
        type=str,
        help="URL of the GPAO API, if not specified nothing will be sent to GPAO"
    )

    return parser.parse_known_args()


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
            result_dict[current_key]['cmd'] = make_absolute(line.strip())
        elif ':' in line:
                current_key, deps = line.split(':')
                current_key = current_key.strip()
                result_dict[current_key] = dict(deps=deps.strip().split(), cmd=None)
        else:
            raise ValueError('File format is invalid')

    return result_dict


# create the project from a makefile_dict and a target, this is a work of art
def create_project(makefile_path, target):

    def build_proj_rec(makefile_dict, jobs, target):
        dependencies = makefile_dict[target]['deps']

        for dependency in dependencies:
            jobs.update(build_proj_rec(makefile_dict, build_proj_rec(jobs), dependency))
        
        cmd = make_absolute(makefile_dict[target]['cmd'])
        
        if not cmd:
            cmd = ';'

        job = Job(target, cmd, dependencies)
        jobs[target] = job
        return jobs

    makefile_dict = parse_makefile(makefile_path)

    jobs = {}
    jobs_dict = build_proj_rec(makefile_dict, jobs, target)

    jobs=jobs_dict.values()

    return Project(ARGS.project_name, jobs)


def save_as_json(ARGS, project):
    #TODO add PPID folder in the JSON path
    json_path = f"{ARGS.JSON}/MM3D_{ARGS.PPID}.json"
    builder_path = f"{ARGS.JSON}/MM3D_{ARGS.PPID}.pickle"

    # check if builder JSON exists
    if os.path.exists(json_path):
        # open the last builder pickle file
        with open(builder_path, "rb") as f:
            projects = pickle.load(f)

        # add dependencies
        for p in projects:
            project.add_dependency(p)
        projects.append(project)
    else:
        projects = [project]

    # save the project as a pickle file
    with open(builder_path, "wb") as f:
        pickle.dump(projects, f)

    # save/override GPAO JSON file
    builder = Builder(projects)
    builder.save_as_json(json_path)

    print(f'GPAO json file saved at {json_path}')


def send_to_api(ARGS, project):
    builder = Builder([project])
    builder.send_project_to_api(ARGS.API)

    # wait for it to complete
    # TODO change later using the API
    time.sleep(30)

    # TODO if failed
    #print("Something went wrong in GPAO")
    #exit(1)


def main():
    ARGS, unknown_ARGS = arg_parser()

    makefile_path = ARGS.makefile if ARGS.makefile else ARGS.file
    project = create_project(makefile_path, ARGS.target)

    if ARGS.JSON:
        save_as_json(project, ARGS)

    if ARGS.API:
        send_to_api(project, ARGS)

    exit(0)


if __name__ == "__main__" :
    main()
