# Config file for CommitHashLogger.ps1 - make one copy of this file per tracked repo.
#
# Rules:
#   - Keep values inside single quotes. Backslashes need no doubling.
#   - A single quote inside a value is written twice: 'Dan''s Repo'
#   - Target and Output may be relative; they are then taken relative to this file's folder.
#   - If a path contains non-English characters, save this file as "UTF-8 with BOM".
@{
    # Root folder of the git repo to read.
    Target      = 'D:\Path\To\TrackedRepo'

    # Folder the log file is written to (created if missing).
    Output      = 'D:\Path\To\OutputFolder'

    # Name of the log file (file name only, no folder).
    LogFileName = 'TrackedRepo_CommitHistory.log'
}
