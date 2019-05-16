URLTitle
=========

A script for Eggdrop IRC bot that detects URLs from public messages on channels and prints out their title

Installation
------------

Just copy urltitle.tcl to your eggdrop scripts directory, set config parameters and add to your Eggdrop configuration file. Works without any configuration, but you can set some options in the script file if you want.

Requirements
------------

The script should work without any additional dependencies, but for the best results, the following tcl packages are recommended:
- **tls:** Required for https URLs
- **htmlparse:** Parse html entities in titles
- **tdom:** More reliable `<title>` tag parsing using xpath (instead of regex).

Broken URLs?
------------
If you encounter any URLs that isn't working properly, please report them under [#10](https://github.com/teeli/urltitle/issues/10).
