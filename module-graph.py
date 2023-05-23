#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from ast import literal_eval
import os
import optparse
import glob

MANIFEST_FILES = ["__manifest__.py", "__openerp__.py", "__terp__.py"]


def load_information_from_description_file(module):
    """
    :param module: The name of the module (sale, purchase, ...)
    """
    for filename in MANIFEST_FILES:
        description_file = os.path.join(module, filename)
        if os.path.isfile(description_file):
            return literal_eval(open(description_file).read())

    return {}


def get_valid_path(paths, module):
    for path in paths:
        full = os.path.join(path, module)
        if any(os.path.exists(os.path.join(full, manifest)) for manifest in MANIFEST_FILES):
            return full
    return None


parser = optparse.OptionParser(usage="%prog [options] [module1 [module2 ...]]")
parser.add_option(
    "-p", "--addons-path", dest="path", help="addons directory", action="append"
)
(opt, args) = parser.parse_args()

if not opt.path:
    opt.path = ["."]

if not args:
    modules = {
        os.path.dirname(f)
        for p in opt.path
        for m in MANIFEST_FILES
        for f in glob.glob(os.path.join(p, "*", m))
    }
else:
    modules = {vp for module in args for vp in [get_valid_path(opt.path, module)] if vp}

all_modules = set(map(os.path.basename, modules))
cli_modules = set(all_modules)  # copy

print("digraph G {")

while modules:
    f = modules.pop()
    module_name = os.path.basename(f)
    all_modules.add(module_name)
    info = load_information_from_description_file(f)
    if info.get("installable", True):
        for name in info.get("depends", []):
            valid_path = get_valid_path(opt.path, name)
            if name not in all_modules:
                if valid_path:
                    modules.add(valid_path)
                else:
                    all_modules.add(name)
                    print(f"\t{name} [color=red]")
            print(f"\t{module_name} -> {name};")
            if module_name in cli_modules:
                print(f"\t{module_name} [color=yellow]")
                cli_modules.discard(module_name)

print("}")
