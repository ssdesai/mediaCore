"""Shared by probe.py: the hook loaded as a module, and the test tables harvested."""
import ast
import collections
import importlib.machinery
import importlib.util
import os
import re

PLACEHOLDER_ROOT = "/fixture/repo"
HEREDOC_PY_RE = re.compile(r"<<'PY'\n(.*?)\nPY\n", re.S)


def load_hook(root):
    path = os.path.join(root, "hooks", "allow-repo-commands.sh")
    loader = importlib.machinery.SourceFileLoader("allow_repo_commands", path)
    spec = importlib.util.spec_from_loader("allow_repo_commands", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class Fallback(dict):
    def __missing__(self, key):
        return PLACEHOLDER_ROOT + "/" + key.lower()


def strings_of(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, (list, tuple)):
        if value and isinstance(value, tuple) and isinstance(value[0], str):
            yield value[0]
        else:
            for item in value:
                for found in strings_of(item):
                    yield found


def harvest(path):
    tables = collections.OrderedDict()
    for body in HEREDOC_PY_RE.findall(open(path).read()):
        try:
            tree = ast.parse(body)
        except SyntaxError:
            continue
        namespace = Fallback(ROOT=PLACEHOLDER_ROOT, NUL="\0")
        for node in tree.body:
            if not isinstance(node, ast.Assign) or len(node.targets) != 1:
                continue
            target = node.targets[0]
            if not isinstance(target, ast.Name) or not target.id.isupper():
                continue
            try:
                value = eval(compile(ast.Expression(node.value), path, "eval"), {}, namespace)
            except Exception:
                continue
            namespace[target.id] = value
            if isinstance(value, list):
                commands = [c for c in strings_of(value) if c.strip()]
                if commands:
                    tables.setdefault(target.id, []).extend(commands)
    return tables
