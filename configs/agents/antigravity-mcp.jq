# Every server of the inventory as Antigravity's mcpServers, each through
# $launcher --scoped. agy reads one global file and can neither scope a server
# to a directory nor fetch a token, and its own HTTP client never finishes
# connecting to some servers (kite), which holds the whole session up. It
# starts stdio servers in the session's working directory, which is what
# --scoped decides by.
#
# Input: the inventory configs/claude writes. Args: $launcher.
([.global // {}] + [.projectLocal[].mcpServers] | add)
| with_entries(.value = {command: $launcher, args: ["--scoped", .key]})
