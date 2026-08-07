-- Close Xcode workspace windows whose file lives under rootPath.
-- Returns the closed paths, one per line. Safe no-op when Xcode isn't running.
--
-- Usage from a Makefile or script (rootPath must be absolute and end with "/"):
--   osascript scripts/xcode-close.applescript "$PWD/" 2>/dev/null || true
--
-- Match by path, not by window title. Title-prefix matching closes unrelated
-- projects that share a prefix ("MyApp" also matches "MyAppTweak"), and two
-- checkouts of the same repo are indistinguishable by title.
--
-- Two implementation constraints, both found the hard way:
-- 1. Never `repeat with d in (get documents)`. That loop variable is a
--    reference to "item i of the list", and Xcode resolves the nested
--    specifier incorrectly — three distinct open workspaces all reported the
--    same `file`, so closing by it hit arbitrary windows. Indexing explicitly
--    with `document j` returns the correct object.
-- 2. `documents` is ordered by window z-order, and closing one shifts every
--    later index. Iterate backwards and close on the same pass.

on run argv
    set rootPath to item 1 of argv
    set closedPaths to {}
    tell application id "com.apple.dt.Xcode"
        repeat with j from (count of documents) to 1 by -1
            try
                if class of document j is workspace document then
                    set p to POSIX path of ((file of document j) as text)
                    if p starts with rootPath then
                        with timeout of 30 seconds
                            close document j saving yes
                        end timeout
                        set end of closedPaths to p
                    end if
                end if
            end try
        end repeat
    end tell
    set AppleScript's text item delimiters to linefeed
    return closedPaths as text
end run
