/*

import xmlparser
import xmltree
import os
import osproc
import times
import strutils
import strtabs
import parseopt
import logging


type GracefulError = object of Exception

func setDataMaintApp(s: var Settings, val: string) =
  s.dataMaintApp = val
  var path, dlls, coreOtName: string
  (path, coreOtName) = splitPath(val)
  if s.dataMaintApp == "":
    s.dataMaintApp = joinPath(path, coreOtName)
  if coreOtName.toLower().endsWith(".exe"):
    s.coreOtName = substr(coreOtName, 0, len(coreOtName) - 5) # odd substr function wants last index rather than length
  else:
    raise newException(GracefulError, "The target file name provided is not an executable")
  (path, dlls) = splitPath(path)
  if dlls.toLower() != "dlls":
    raise newException(GracefulError,"Unexpected folder structure")
  s.otBasePath = path & os.DirSep

func setDataMaintApp(s: var Settings) =
  ##
  ## Initializes settings based upon the current app path.  This is used in all scenarios other than when
  ## a 'replace' is performed
  ##
  if not symlinkExists(s.currAppPath):
    raise newException(GracefulError, "App must be run via symlink when not performing a replace")
  setDataMaintApp(s, s.currAppPath)


func rCoreOtName(s: Settings): string =
  nirvanaPrefix & s.coreOtName

func dllPath(s: Settings): string =
  return s.otBasePath & "Dlls" & os.DirSep

func dataMaintPdb(s: Settings): string {.inline.} =
  return dllPath(s) & s.coreOtName & ".pdb"

func dataMaintCfg(s: Settings): string {.inline.} =
  return dllPath(s) & s.coreOtName & ".exe.config"

func dataMaintAppRenamed(s: Settings): string {.inline.} =
  return dllPath(s) & rCoreOtName(s) & ".exe"

func dataMaintPdbRenamed(s: Settings): string {.inline.} =
  return dllPath(s) & rCoreOtName(s) & ".pdb"

func dataMaintCfgRenamed(s: Settings): string {.inline.} =
  return dllPath(s) & rCoreOtName(s) & ".exe.config"

func timeFileName(s: Settings): string {.inline.} =
  return s.otBasePath & ".sodm.txt"


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


proc replace(s: Settings): bool =
  # rename old app, pdb, and config
  # start with the PDB file. If there isn't one we assume that a replace has already been done
  if os.existsFile(s.dataMaintPdb):
    if os.existsFile(s.dataMaintPdbRenamed):
      os.removeFile(s.dataMaintPdbRenamed)
    os.moveFile(s.dataMaintPdb, s.dataMaintPdbRenamed)
  else:
    echo "Already replaced, exiting"; return false
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
  # make a link to the replaced app and name it the same as Nirvana's app
  os.createSymlink(destPath, s.dataMaintApp)
  return true


proc restore(s: Settings): bool =
  # restore should be run directly from the installed app location
  if s.currAppPath != s.dataMaintApp:
    raise newException(GracefulError, "Not running from the correct folder")
  if os.existsFile(s.dataMaintPdb) or os.existsFile(s.dataMaintCfg):
    raise newException(GracefulError, "The application does not appear to be replaced - no action taken")
  os.moveFile(s.dataMaintPdbRenamed, s.dataMaintPdb)
  os.moveFile(s.dataMaintCfgRenamed, s.dataMaintCfg)
  os.removeFile(s.dataMaintApp)
  os.moveFile(s.dataMaintAppRenamed, s.dataMaintApp)
  return true


proc cliReplaceUsage(s: Settings) =
  echo """Usage:
  sodm replace appPath
  where appPath is the path to the OTDataMaintenanceXXXX.exe file to be replaced.
Examples:
  sodm replace "c:\Program Files (x86)\Nirvana\OT2019\Dlls\OTDataMaintenance2019.exe""""

proc resolvePath(path: string): string =
  if isAbsolute(path):
    return path
  return absolutePath(normalizedPath(path))

proc cliReplace(p: var OptParser, s: var Settings) =
  p.next()
  case p.kind
    of cmdLongOption, cmdShortOption, cmdEnd:
      cliReplaceUsage(s)
    of cmdArgument:
      s.setDataMaintApp(resolvePath(p.key))
  if replace(s):
    echo "Replace complete"


proc cliRestore(p: var OptParser, s: Settings) =
  p.next()
  if p.kind != cmdEnd:
    raise newException(GracefulError, "Restore takes no arguments")
  if restore(s):
    echo "Restore complete"


proc compact(s: Settings): bool =
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
  return true


proc cliCompact(s: Settings) =
  if compact(s):
    echo "Compaction complete"

proc cliUsage(s: Settings) =
  let usageText =
    """Usage:
  sodm [action] [args]
Actions:
  replace - replace the specified executable
  restore - restore the original executable
  """
  echo usageText

*/

const (
  nirvanaPrefix = 'nirv'
)

struct Settings {
  core_ot_name string
  data_maint_app string
  ot_base_path string    // the path where OT is installed
  curr_app_path string   // the full path to this application
}

fn main() {
  println ('Smart OmniTrader Data Maintenance (sodm)')
}

/*
when isMainModule:
  try:
    var s = Settings(currAppPath: getAppFilename())
    var p = initOptParser("")
    p.next()
    case p.kind
      of cmdArgument:
        case p.key
          of "replace":
            cliReplace(p, s)
          of "restore":
            s.setDataMaintApp()
            cliRestore(p, s)
          of "/Silent":
            s.setDataMaintApp()
            cliCompact(s) # Nirvana passes this option
          else: cliUsage(s)
      of cmdLongOption, cmdShortOption:
        cliUsage(s)
      of cmdEnd:
        s.setDataMaintApp()
        cliCompact(s)
  except GracefulError:
    echo getCurrentExceptionMsg()
*/
