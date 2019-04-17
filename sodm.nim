import xmlparser
import xmltree
import os
import osproc
import times
import strutils
import strtabs
import parseopt
import logging

const coreOtName = "OTDataMaintenance2019"
const rCoreOtName = "nirv" & coreOtName

type Settings = object
  otBasePath: string    # the path where OT is installed
  currAppPath: string   # the full path to this application

func dllPath(s: Settings): string =
  return s.otBasePath & "Dlls" & os.DirSep

func dataMaintApp(s: Settings): string {.inline.} =
  return dllPath(s) & coreOtName & ".exe"

func dataMaintPdb(s: Settings): string {.inline.} =
  return dllPath(s) & coreOtName & ".pdb"

func dataMaintCfg(s: Settings): string {.inline.} =
  return dllPath(s) & coreOtName & ".exe.config"

func dataMaintAppRenamed(s: Settings): string {.inline.} =
  return dllPath(s) & rCoreOtName & ".exe"

func dataMaintPdbRenamed(s: Settings): string {.inline.} =
  return dllPath(s) & rCoreOtName & ".pdb"

func dataMaintCfgRenamed(s: Settings): string {.inline.} =
  return dllPath(s) & rCoreOtName & ".exe.config"

func installedApp(s: Settings): string {.inline.} =
  return s.dllPath & splitPath(s.currAppPath).tail

func timeFileName(s: Settings): string {.inline.} =
  return s.otBasePath & ".sdm.txt"


proc updateConfigXml(xml: XmlNode, otPath: string, asOfTime: Time): seq[string] =
  var config: XmlNode
  var configIdx = -1
  for idx in 0..<len(xml):
    config = xml[idx]
    if config.kind == xnElement and config.tag == "CompactDB":
      configIdx = idx
      break
  if configIdx == -1:
    return @[]

  var dirs: seq[string] = @[]
  var masks: seq[string] = @[]
  let newConfig = newElement("CompactDB")
  var fileCounter = 0
  let otPathLen = len(otPath)

  # this is a helper proc that adds file elements to both the XML and the result sequence
  let addFileElement = proc(full: string, part: proc(): string, res: var seq[string]) =
    let fi = getFileInfo(full)
    if fi.lastWriteTime >= asOfTime:
      let p = part()
      res.add(p)
      var el = newElement("add")
      el.attrs = newStringTable({"key": "File" & $fileCounter, "value": p})
      inc fileCounter
      newConfig.add(el)

  # read in the dirs and masks and generate file entries instead
  for i in countdown(len(config)-1, 0):
    let entry = config[i]
    if entry.kind != xnElement:
      continue
    let key = entry.attr("key")
    let value = entry.attr("value")
    if key.startsWith("Dir"):
      dirs.add(value)
    elif key.startsWith("Mask"):
      masks.add(value)
    else:
      # go ahead and add back the explicit file elements specified by Nirvana
      addFileElement(otPath & value, proc (): string = value, result)

  # now walk the directories and globs specified by Nirvana and generate file elements
  for mask in masks:
    let glob = '*' & mask
    for dir in dirs:
      for fn in os.walkFiles(otPath & dir & os.DirSep & glob):
        addFileElement(fn, proc (): string = fn[otPathLen..^1], result)

  # replace the old CompactDB XML node with the new one
  xml.insert(newConfig, configIdx)
  xml.delete(configIdx+1)


proc getUpdateTime(s: Settings): Time =
  var f: File
  let tfn = s.timeFileName()
  if existsFile(tfn):
    f = open(tfn, fmRead)
    result = parseTime(readLine(f), "yyyy-MM-dd'T'HH:mm:sszzz", utc())
    close(f)
  else:
    let ef = s.otBasePath & "exiting.txt"
    # the exiting.txt file may not exist because OT blows it away while running
    if existsFile(ef):
      result = getLastModificationTime(ef)
    else:
      # when all else fails fall back to the brokerage file, which seems to be modified with every run
      result = getLastModificationTime(s.otBasePath & "Brokerage/Brokerage.otd")


proc install(s: Settings) =
  # rename old app, pdb, and config
  # start with the PDB file. If there isn't one we assume that an install has already been done
  if os.existsFile(s.dataMaintPdb):
    if os.existsFile(s.dataMaintPdbRenamed):
      os.removeFile(s.dataMaintPdbRenamed)
    os.moveFile(s.dataMaintPdb, s.dataMaintPdbRenamed)
  else:
    echo "Already installed, exiting"; return
  if os.existsFile(s.dataMaintApp):
    if os.existsFile(s.dataMaintAppRenamed):
      os.removeFile(s.dataMaintAppRenamed)
    os.moveFile(s.dataMaintApp, s.dataMaintAppRenamed)
  if os.existsFile(s.dataMaintCfg):
    if os.existsFile(s.dataMaintCfgRenamed):
      os.removeFile(s.dataMaintCfgRenamed)
    os.moveFile(s.dataMaintCfg, s.dataMaintCfgRenamed)

  # copy this app to the DLL dir (if that's not already the running instance)
  var destPath = s.currAppPath
  if not s.currAppPath.startsWith(s.dllPath):
    destPath = s.dllPath() & splitPath(s.currAppPath).tail
    os.copyFile(s.currAppPath, destPath)
  # make a link to the installed app and name it the same as Nirvana's app
  os.createSymlink(destPath, s.dataMaintApp)


proc uninstall(s: Settings) =
  # uninstall should be run directly from the installed app location
  if s.currAppPath != s.installedApp:
    writeLine(stderr, "Not running from the correct folder"); return
  if os.existsFile(s.dataMaintPdb) or os.existsFile(s.dataMaintCfg):
    writeLine(stderr, "The application does not appear to be installed - no action taken"); return
  os.moveFile(s.dataMaintPdbRenamed, s.dataMaintPdb)
  os.moveFile(s.dataMaintCfgRenamed, s.dataMaintCfg)
  os.removeFile(s.dataMaintApp)
  os.moveFile(s.dataMaintAppRenamed, s.dataMaintApp)


proc cliInstall(p: var OptParser, s: var Settings) =
  while true:
    p.next()
    case p.kind
      of cmdLongOption, cmdShortOption:
        if p.key != "basedir":
          writeLine(stderr, "Invalid option: ", p.key); return
        s.otBasePath = p.val
      of cmdArgument:
        writeLine(stderr, "Only one command may be given")
      of cmdEnd:
        break
  install(s)
  echo "Install complete"


proc cliUninstall(p: var OptParser, s: Settings) =
  while true:
    p.next()
    case p.kind
      of cmdLongOption, cmdShortOption:
        writeLine(stderr, "No options are allowed"); return
      of cmdArgument:
        writeLine(stderr, "Only one command may be given"); return
      of cmdEnd:
        break
  uninstall(s)
  echo "Uninstall complete"


proc compact(s: Settings) =
  let origFile = s.dataMaintCfgRenamed

  # read config file into memory
  let xml = loadXml(origFile)

  let updateTime = getUpdateTime(s)
  # update the XML config with files that have changes since the last run
  let files = updateConfigXml(xml, s.otBasePath, updateTime)
  if len(files) > 0:
    # set up logging
    let logFile = open(s.currAppPath & ".log", fmAppend)
    try:
      let l = newFileLogger(logFile, lvlAll, verboseFmtStr)
      addHandler(l)
      # move config file to backup
      let backFile = origFile & ".bak"
      os.moveFile(origFile, backFile)
      try:
        # create a new temporary config file
        let f1 = open(origFile, fmWrite)
        f1.write(xml)
        f1.close()
        try:
          # inform the user of which files are being compacted
          echo "Running '", s.dataMaintAppRenamed, "' to compact the following files: "
          for f in files: echo f
          # launch real OTDataMaint program
          let rslt = execProcess(s.dataMaintAppRenamed, "", [], nil, {poStdErrToStdOut, poEvalCommand, poDaemon})
          if rslt != "":
            info("Output from Nirvana data maint: ", rslt)
          # now log the files that were compacted
          for f1 in files:
            info("Compacted ", f1)
          writeLine(logFile, "")
        finally:
          os.removeFile(origFile)
      finally:
        # restore original config file
        os.moveFile(backFile, origFile)
    finally:
      logFile.close()

  # store date of last run to be used in detecting newer files
  let f = open(s.timeFileName(), fmWrite)
  writeLine(f, utc(now()))
  f.close()


proc cliCompact(s: Settings) =
  compact(s)
  echo "Compaction complete"


when isMainModule:
  echo "Smart OmniTrader Data Maintenance"
  var s = Settings(otBasePath: r"C:\Program Files (x86)\Nirvana\OT2019\", currAppPath: os.getAppFilename())
  # command line examples:
  # app install - installs app in current dir
  # app install [basedir] - installs app in specified OT dir
  # app uninstall - removes app from current dir
  # app - runs as if it is the maintenance program.  Install should have already been performed.
  var p = initOptParser("", {'b'}, @["basedir"], false)
  p.next()
  case p.kind
    of cmdArgument:
      case p.key
        of "install": cliInstall(p, s)
        of "uninstall": cliUninstall(p, s)
        of "/Silent": cliCompact(s) # Nirvana passes this option
    of cmdLongOption, cmdShortOption:
      writeLine(stderr, "No options are allowed for the default command")
    of cmdEnd:
      cliCompact(s)

