import argparse
from pathlib import Path
import sys
import click
import numpy as np

from gpao.builder import Builder
from gpao.project import Project
from gpao.job import Job

import glob
import os

from datetime import datetime

def arg_parser():
    """ Extraction des arguments de la ligne de commande """
    parser = argparse.ArgumentParser()

    parser.add_argument(
        'makefile',
        nargs='?',
        default=None,
        help="makefile"
    )

    parser.add_argument(
        '--file',
        '-f',
        type=str,
        help="makefile"
    )

    parser.add_argument(
        'rule',
        type=str,
        help="rule for the makefile"
    )

    parser.add_argument(
        '--jobs',
        '-j',
        metavar='N',
        type=int,
        help='an integer for the number of jobs'
    )

    parser.add_argument(
        '--JSON',
        nargs="?",
        const='MM3D_GPAO.json',
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
        '--silent',
        '-s',
        action='store_true',
        help="Silent operation; do not print the commands as they are executed."
    )

    return parser.parse_args()

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

ARGS = arg_parser()

cmds = dict()

makefile_path = ARGS.makefile if ARGS.makefile else ARGS.file

with open(makefile_path) as mf:
    filename = os.path.basename(makefile_path)
    cmd = filter(lambda x : x.strip() != '' and x.startswith('\t'), mf.read().split('\n'))
    cmd = list(cmd)
    cmds = [x.strip() for x in cmd]

makefile = dict(
    all=cmds
)

jobs = []
for i, cmd in enumerate(makefile[ARGS.rule]):
    job = Job(f'MM3D_{i}', make_absolute(cmd))
    jobs.append(job)

project = Project(ARGS.project_name, jobs)

builder = Builder([project])

if(ARGS.JSON):
    builder.save_as_json(ARGS.JSON)
    print(f'GPAO json file saved at {ARGS.JSON}')
