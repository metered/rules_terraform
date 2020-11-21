from __future__ import print_function

import argparse
import tarfile
import os
from os.path import realpath

import sys

parser = argparse.ArgumentParser(
    fromfile_prefix_chars='@',
    description='Description')

parser.add_argument(
    '--input_tar', action='append', default=[], nargs=2, metavar=('modulepath', 'tar'),
    help="Bundle of files to add to module")
parser.add_argument(
    '--input_file', action='append', default=[], nargs=2, metavar=('tgt_path', 'input_file'),
    help="Bundle of files to add to module")

parser.add_argument(
    '--output', action='store', required=True,
    help="Location of output archive")

def _combine_paths(left, right):
  result = left.rstrip('/') + '/' + right.lstrip('/')

  # important: remove leading /'s: the zip format spec says paths should never
  # have a leading slash, but Python will happily do this. The built-in zip
  # tool in Windows will complain that such a zip file is invalid.
  return result.lstrip('/')

def main(args):
    output = tarfile.open(args.output, "w:gz")

    # TODO: make sure we can't overwrite existing files

    # iterate files & add them
    for arcname, f in args.input_file:
        if os.path.isfile(realpath(f)):
            output.add(realpath(f), arcname=arcname)
            continue

        # We found a directory. Expand it.
        # dst_path = _combine_paths(arcname, dst_path)
        for root, subdirs, subfiles in os.walk(f):
            for subfile in subfiles:
                subpath = os.path.join(root, subfile)
                output.add(realpath(subpath), arcname=_combine_paths(arcname, subpath[len(f)+1:]))

        

    # iterate tars, iterate files & add them
    for modulepath, t in args.input_tar:
        with tarfile.open(t, "r") as tar:
            for tarinfo in tar.getmembers():
                if modulepath:
                    tarinfo.name = "modules/%s/%s" % (modulepath, tarinfo.name)
                f = tar.extractfile(tarinfo)
                output.addfile(tarinfo, f)

    output.close()


if __name__ == '__main__':
    try:
        main(parser.parse_args())
    except ValueError as e:
        print(e, file=sys.stderr)
        exit(1)
