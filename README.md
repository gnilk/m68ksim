# m68ksim
Based on: https://github.com/kstenerud/Musashi
Using: 
	Dear IMGui, https://github.com/ocornut/imgui
	Amiga Hunk Parser, https://github.com/emoon/AmigaHunkParser

Note: The Hunk parser is forked in the project as it contains some minor fixes...


Implements a very simple debugger/stepper in the simulator context.
Allows stepping through a program.

Use CMake to build. Run "init.sh" to install dependencies.

Start: dbgui amiga_file.exe

The Debugger will search for source code like this:
	./src/file
	../src/file

Commands in the debugger:
- mt address, memory texture from address
- m address, view memory from address
- sr reg value, set registry (d0..d7, a0..a7) to value
- j address/symbol, jump to address or symbol
- rt address/symbol, run-to address or symbol


Screenshot
![Screenshot](/screenshot/Amiga_Debugger_v3.png)