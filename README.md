# General_stuff

Various unrelated scripts and who knows what...

- add_nuttx_lib.sh - work in progress on automated library adder base on GDB scanning for Low-Level register calls in IDF.
- backtrace.sh - dump in Arduino backtrace adresses and get actual readable backtrace. But this should be already implemented in Arduino IDE should no longer be needed.
- chown_serial.sh - change ownership of the serial port (declared in parameter). This was sometimes needed when there were problems accessing it.
- kill_serial.sh - kill all processes attached to specified serial port. This is used when something hangs on the - port and there are problems using it again.
- fresh_fedora_setup.sh - big script doing **MY PERSONAL** setup of various configs - some are done manually!
- grade.sh - UP-grade or DOWN-grade python package as needed by IDF.
- idfpyflashmonitor.sh - as the name says - it calls `idf.py flash monitor` for port specified in argument
- launch.json - Not sure, probably some debug config for M$ VS code or something like that.
- lty.sh - print list of /dev/tty ports
- my_find.sh - shortcut for finding files
my_grep_search.sh - shortcut for searching text in files
- ocd.sh - script for setting up OCD and GDB for ESP (if you don't know what those shortcuts mean, it probably looks funny)
- pre-commit - arduino-esp32 checker which compiles changed examples and libraries for all chips and prevents commit if errors occur.
- serial.sh - simply open serial monitor for ESP32 as it would an Arduinio IDE - but in terminal, so you can have more of them.
- switch.sh - my developer script which is changing arduino fork that will be actually used for compilation in Arduino IDE


debug_and_commit folder
- precommit.sh - backup work-in-progress file and remove all debug outputs.
- aftercommit.sh - simple restore backup file with debug outputs
