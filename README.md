# ourWorld Album Recoverer (haxe)

## A haxe application for windows that will download photorec and read/undelete jpegs from the selected drive and keep only ones matching the resolution of ourWorld album photos

### Goal

The goal of this script is to get back as many album photos as possible that would have been on the computer at one point from browser cache or adobe air cache.

# Simple Usage
This has been compiled for the C++ windows target and can be found on the releases page.\
Simply download the windows release and run AlbumRecoverer.exe.

# Simple Compilation

In order to build for the C++ target you will need the respective C++ tools installed which will not be documented here,
building will result in making an executable that will use the neko interpreter installed on your system to run it and if
the appropriate tools for compiling to C++ aren't installed then it will fail and you will still have a neko executable built.

```
haxelib install build.hxml
haxe build.hxml
```
