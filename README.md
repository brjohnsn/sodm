# sodm
## Smart OmniTrader Data Maintenance

Runs the OTDataMaintenanceXXXX (OTDM) tool only on files that have actually changed during the most recent OmniTrader (OT) session.

## What's the benefit?
1. Time savings. After each OT session OTDM appears to perform maintenance on EVERY file with a OTP, OTD, or OTR extension in the Profiles and Results directories regardless of whether it was ever altered during that session. In my case this amounted to around 150 files (2.4 GB of data at the time). Quite often I had only opened one or two profiles and had to wait up to 5 minutes for the tool to finish running before I could shut down the machine or start a backup. Even more frustrating for me was waiting for OTDM to run on files after a crash in OmniTrader (typically due to some sort of memory error). As if it weren't bad enough that I had the hassle of a program error I then had to wait for the maintenance program to finish before I could get back into OT and continue my work. In past versions OT was unable to start up if the OTDM program was running but that no longer seems to be the case in 2019.
1. Slimmer backups. I typically back up my data in case disaster strikes and there's no reason I should have to back up 2+ GB of data when only 200 MB of data was altered.

## How does it work?
### At installation...
Upon installing sodm in the OT directory, sodm renames the OTDM tool and it's associated configuration file. It then creates a link to itself with the name OmniTraderDataMaintenanceXXXX.exe so that sodm itself is called from OT while OT is shutting down.
### After each OT session...
1. OT executes the OTDM program (which is actually sodm after installation)
1. sodm analyzes what has actually changed in the Profiles and Results directories and generates a config file for Nirvana's OTDM tool
1. sodm executes Nirvana's OTDM tool to perform maintenance on the files that have changed

## Files created/altered by sodm
sodm creates two files of it's own in the OT directory:
* In the OT\ directory it creates a file named .sodm.txt.  This file is used to track the most recent time sodm was run so that it knows which files are newly altered
* In the OT\Dlls directory sodm writes a log file to track each compaction session.  This file is informational only and can be deleted if the user so chooses.

In addition sodm renames a few files from the OT distribution.  Those files will be renamed to their original values after executing the "restore" subcommand.  If something should happen where sodm causes an issue with the OT installation, that OT installation can be repaired via the Windows installer.

## OT updates disable sodm
OT overwrites all program files during an update.  As a result this disables sodm because the update clobbers the links it created.  Therefore after each OT update you will also have to reinstall sodm to re-establish those links.  Please see the "How to reinstall" topic below to see how this is done.


## How to build
1. Install nim (https://nim-lang.org/install.html)
1. Clone or download this repository
1. Navigate to the location to which the repository was downloaded and execute the following command:
    ```
    nim build sodm
    ```
1. Once the build completes you will find the binary (sodm.exe) in the bin folder

## How to install
The binary produced during the build process is all you need.  To "install" it you can either copy it manually to the OT\Dlls folder and then run the program using the "replace" subcommand:
```
copy bin\sodm.exe "c:\Program Files (x86)\Nirvana\OT2019\Dlls"
cd "c:\Program Files (x86)\Nirvana\OT2019\Dlls"
sodm.exe replace OTDataMaintenance2019.exe
```
or you may execute the binary from any location and provide the full path to the name of the target executable to be replaced
```
bin\sodm.exe replace "c:\Program Files (x86)\Nirvana\OT2019\Dlls\OTDataMaintenance2019.exe"
```

## How to reinstall
If you need to reinstall sodm you may simply re-run it from the OT\Dlls folder in which it is already installed
```
sodm.exe replace OTDataMaintenance2019.exe
```

## How to uninstall
To "uninstall", navigate to the OT\Dlls folder from the command prompt and execute sodm via it's link passing the "restore" command.
```
cd "c:\Program Files (x86)\Nirvana\OT2019\Dlls"
OTDataMaintenance2019.exe restore
```