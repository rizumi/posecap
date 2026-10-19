-- Xcode 27.1 Device Hub adapter. All user values arrive as argv, never source code.
-- Layout paths are version-specific. Controls are selected by semantic AXHelp,
-- not button indexes. Every operation validates the selected device again.
on matchingRow(deviceName, osVersion)
    tell application "System Events" to tell process "DeviceHub"
        if (count of windows) is not 1 then error "Expected exactly one Device Hub window."
        set deviceOutline to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of splitter group 1 of group 1 of window 1
        set matches to {}
        repeat with candidate in (rows of deviceOutline)
            try
                set labels to value of every static text of UI element 1 of candidate
                if (count of labels) is 3 and labels contains deviceName and labels contains osVersion and labels contains "Simulator" then
                    set end of matches to contents of candidate
                end if
            end try
        end repeat
        if (count of matches) is not 1 then error "Cannot uniquely identify the requested Simulator in Device Hub."
        return item 1 of matches
    end tell
end matchingRow

-- Resolve the unique row once per subprocess, then recheck that same row and
-- window around actions. Do not walk the entire sidebar for every assertion.
on assertTarget(targetRow, deviceName, osVersion)
    tell application "System Events" to tell process "DeviceHub"
        if selected of targetRow is not true then error "Device Hub selection changed; stopping GUI operations."
        set titleText to name of window 1
        if titleText is not (deviceName & " – iOS " & osVersion) and titleText is not (deviceName & " – iPadOS " & osVersion) then error "Device Hub window title does not match the requested Simulator."
    end tell
end assertTarget

on run argv
    if (count of argv) is not 4 then error "Invalid Device Hub adapter arguments."
    set deviceName to item 1 of argv
    set osVersion to item 2 of argv
    set operation to item 3 of argv
    set controlHelp to item 4 of argv
    if operation is not in {"prepare", "check", "probe", "click", "probe-orientation", "set-orientation", "read-orientation", "probe-rotation", "rotate"} then error "Unknown GUI operation."
    with timeout of 25 seconds
        tell application "System Events"
            if not (exists process "DeviceHub") then error "Open Device Hub before requesting posture or rotation changes."
        end tell
        set targetRow to my matchingRow(deviceName, osVersion)
        if operation is "prepare" then
            tell application "System Events" to tell process "DeviceHub"
                if selected of targetRow is not true then set selected of targetRow to true
            end tell
            -- Wait only for the selection/title, not for application readiness.
            repeat with attempt from 1 to 20
                try
                    my assertTarget(targetRow, deviceName, osVersion)
                    return "target-confirmed"
                on error messageText
                    if attempt is 20 then error messageText
                    delay 0.1
                end try
            end repeat
        end if
        if operation is in {"probe-orientation", "set-orientation", "read-orientation", "probe-rotation", "rotate"} then
            -- The dynamic Device menu is populated only while Device Hub is active.
            tell application id "com.apple.dt.Devices" to activate
            tell application "System Events" to tell process "DeviceHub" to set frontmost to true
            repeat with attempt from 1 to 20
                tell application "System Events" to tell process "DeviceHub" to set isFront to frontmost
                if isFront then exit repeat
                delay 0.1
            end repeat
            my assertTarget(targetRow, deviceName, osVersion)
            if operation is in {"probe-rotation", "rotate"} then
                if controlHelp is not in {"Rotate Left", "Rotate Right"} then error "Unknown rotation direction."
                tell application "System Events" to tell process "DeviceHub"
                    if frontmost is not true then error "Device Hub must be frontmost for rotation."
                    -- Open the dynamic menu before dispatch. The caller verifies
                    -- orientation separately; successful AXPress is not readback.
                    if operation is "rotate" then click menu bar item "Controls" of menu bar 1
                    set controlsMenu to menu 1 of menu bar item "Controls" of menu bar 1
                    set candidates to every menu item of controlsMenu whose name is controlHelp
                    if (count of candidates) is not 1 then error "Cannot uniquely identify the requested rotation item."
                    set targetItem to item 1 of candidates
                    if enabled of targetItem is not true then error "Requested rotation item is disabled."
                end tell
                my assertTarget(targetRow, deviceName, osVersion)
                if operation is "probe-rotation" then return "control-confirmed"
                tell application "System Events" to tell process "DeviceHub"
                    if frontmost is not true then error "Device Hub lost foreground before rotation."
                    click targetItem
                end tell
                my assertTarget(targetRow, deviceName, osVersion)
                return "dispatched"
            end if
            tell application "System Events" to tell process "DeviceHub"
                if frontmost is not true then error "Device Hub must be frontmost for orientation control."
                set orientationMenu to menu 1 of menu item "Orientation" of menu 1 of menu bar item "Device" of menu bar 1
                if operation is "read-orientation" then
                    set markedTitles to {}
                    repeat with titleText in {"Portrait", "Portrait Upside Down", "Landscape Left", "Landscape Right", "Face Up", "Face Down"}
                        set candidates to every menu item of orientationMenu whose name is (contents of titleText)
                        if (count of candidates) is not 1 then error "Unexpected Orientation menu structure."
                        try
                            if value of attribute "AXMenuItemMarkChar" of item 1 of candidates is "✓" then set end of markedTitles to contents of titleText
                        end try
                    end repeat
                else
                    if controlHelp is not in {"Portrait", "Landscape Left"} then error "Unknown orientation preset."
                    set candidates to every menu item of orientationMenu whose name is controlHelp
                    if (count of candidates) is not 1 then error "Cannot uniquely identify the requested orientation item."
                    set targetItem to item 1 of candidates
                    if enabled of targetItem is not true then error "Requested orientation item is disabled."
                    set alreadySelected to false
                    try
                        set alreadySelected to value of attribute "AXMenuItemMarkChar" of targetItem is "✓"
                    end try
                end if
            end tell
            my assertTarget(targetRow, deviceName, osVersion)
            if operation is "read-orientation" then
                if (count of markedTitles) is not 1 then return "unknown"
                return item 1 of markedTitles
            end if
            if operation is "probe-orientation" then return "control-confirmed"
            if alreadySelected then return "unchanged"
            tell application "System Events" to tell process "DeviceHub"
                if frontmost is not true then error "Device Hub lost foreground before orientation control."
                click targetItem
            end tell
            my assertTarget(targetRow, deviceName, osVersion)
            return "dispatched"
        end if
        my assertTarget(targetRow, deviceName, osVersion)
        if operation is "check" then return "target-confirmed"
        if controlHelp is not in {"Closed", "Partially Open", "Open", "Rotate Right"} then error "Unknown posture or rotation control."
        tell application "System Events" to tell process "DeviceHub"
            set controlsGroup to group 3 of splitter group 1 of group 1 of splitter group 1 of group 1 of window 1
            set matches to every button of controlsGroup whose help is controlHelp
            if (count of matches) is not 1 then error "Cannot uniquely identify the requested Device Hub control."
            set targetControl to item 1 of matches
            if enabled of targetControl is not true then error "The requested Device Hub control is disabled."
        end tell
        if operation is "probe" then return "control-confirmed"
        my assertTarget(targetRow, deviceName, osVersion)
        tell application "System Events" to click targetControl
        my assertTarget(targetRow, deviceName, osVersion)
        return "dispatched"
    end timeout
end run
