import os, strutils, osproc

const protosDir = "tests/protos"

proc main() =
  var failed = false
  var passedCount = 0
  var failedCount = 0

  echo "Starting tests for all .proto files in ", protosDir

  for kind, path in walkDir(protosDir):
    if kind == pcFile and path.endsWith(".proto"):
      echo "---------------------------------------------------"
      echo "Testing ", path

      # Create a temporary test file that imports the proto
      # We need to use absolute path for the proto file to be safe,
      # or relative to the test file.
      # Since we write temp_test.nim in tests/, the proto path should be relative to tests/
      # path is "tests/protos/xxx.proto".
      # So inside tests/temp_test.nim, we should refer to it as "protos/xxx.proto"
      # OR just use the absolute path.

      let absProtoPath = absolutePath(path)

      let nimContent = """
import ../src/nimproto3

# We need to suppress warnings to make output cleaner, but for now let's see everything
importProto3 "$1"

echo "Successfully compiled and imported $1"
""" % [absProtoPath.replace("\\", "/")]

      let testFile = "tests/temp_test_" & path.splitFile.name & ".nim"
      writeFile(testFile, nimContent)

      # Run the test
      # We use -d:showGeneratedProto3Code to see output if it fails (optional)
      # But mostly we care if it compiles.
      let (output, exitCode) = execCmdEx(
          "nim c -r --hints:off --warnings:off " & testFile)

      if exitCode != 0:
        echo "FAILED: ", path
        echo "Output:"
        echo output
        failed = true
        failedCount.inc
      else:
        echo "PASSED: ", path
        passedCount.inc

      removeFile(testFile)
      removeFile(testFile.replace(".nim", "")) # Remove generated binary file

  echo "---------------------------------------------------"
  echo "Test Summary:"
  echo "Passed: ", passedCount
  echo "Failed: ", failedCount

  if failed:
    quit(1)
  else:
    echo "All tests passed!"

main()
