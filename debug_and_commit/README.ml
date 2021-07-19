# Clean before commit and return to previous state after commit

When I use lot's of debug prints and need to commit.
Script **precommit.sh** will make backup of all **.c** **.cpp** and **.h** files and remove debug outputs from the original.
After cleaning with **precommit.sh** you can commit your cleaned changes and follow with **aftercommit.sh** which will simply use the backedup files and move them to original place as if nothing happend.

This script is written for my specific needs, but feel free to modify it to your own.
Script will remove all lines matching "DEBUGLN" || "DEBUGF" || "// debug" || "#include "DEBUG.h"

Folder test_data/ contains sample files with pseudocode to demonstate and test behaviour.

