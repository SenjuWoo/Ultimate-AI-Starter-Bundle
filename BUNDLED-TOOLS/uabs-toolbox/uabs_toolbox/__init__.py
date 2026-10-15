"""UABS toolbox: the project tools a chat does not load, one call away.

Task MCP servers (game forges, editors, browser automation, GitHub, Melty ...)
are kept out of every chat to save tokens. This package is the one small MCP
server that stays on: it finds them by task, starts the one a task needs on
first use and passes its calls through, so nothing needs a restart or a config
change.
"""

__version__ = "1.0.0"
