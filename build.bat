@echo off

odin build src -out:D3D10Demo2D.exe ^
-microarch:generic -o:speed ^
-subsystem:windows -resource:res/main.rc ^
-collection:lib=lib
