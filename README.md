# CMake - VersionInfoTarget

This project (`CMakeVersionInfoTarget`) generates a header and source file
for C/C++ that contains version information about the current project.

These files are generated during the build, not during configuration so the
project version information should be as accurate as possible.

The following information is made available to any target linking to the target:

- project name
- project version (major, minor & patch)
- compiler id (GNU, MSVC, Clang)
- compiler version
- platform architecture (x86, AMD64, ARM)
- configuration (Debug or Release)

Optionally, this module can query and store Git repository information.

- git commit hash (which was checked out at time of compile)
- git commit user (name & email)
- git commit author (name & email)
- git commit date
- git repo status (indicates if there was uncommitted changes at compile time)

## Why?

You want to have the configuration and version information built directly into
your binary (library or executable) so that this important metadata cannot be
separated from the artifact itself.

Imagine a hypothetical scenario...

1. You deploy a nice shiny new program into production and it seems to be
   running perfectly... until a client reports a bug.

1. You ask the client for the version they are running so you can try and
   reproduce the bug locally.

   *NOTE: this assumes your program has an 'About' menu or a `--version` flag*

1. You checkout that version and try to re-build... but you can't seem to
   re-create the bug!

What could be wrong?

- The client is crazy
- The program was compiled on Friday the 13th
- Maybe the build environment was different when you compiled the binary?
  - Different compiler version?
  - Uncommitted changes in the repository?

How does this Module help?

This CMake module embeds fresh version information into your targets at compile
time, allowing you to always know the exact version details of a given library.

If your project is a Git repository, it can even tell you if there were
uncommitted changes at the time it was compiled!

## Usage - Adding the submodule

To start using this project you only need to copy the
`VersionInfoTarget.cmake` file into your project directory.

*NOTE: Copying the file is the easiest way, but its better to include this
project as a git submodule. This avoids file duplication!*

## Usage - CMake

Copy the module file into your project (*or add as a git submodule*)

Then you just need to include it from your `CMakeLists.txt` file like so:

```cmake
include(3rd/CMakeVersionInfoTarget/VersionInfoTarget.cmake)
```

This will import a function `add_version_info_target` with the following call spec:

```cmake
add_version_info_target(NAME <unique_target_name>
    [LINK_TO targets...]
    [NAMESPACE namespaces...]
    [LANGUAGE language]
    [GIT_WORK_TREE <git_work_tree>]
    [PROJECT_NAME <name>]
    [PROJECT_VERSION <version>]
)
```

Calling this function generates a static library target that always contains
up-to-date version information.

## Usage - Parameters

*see comment in the VersionInfoTarget.cmake file for parameter details.*

## Usage - Minimum Reproducible Example (C++)

```cmake
# CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(HelloVersion VERSION 1.2.3 LANGUAGES CXX)
include("./3rd/CMakeVersionInfoTarget/VersionInfoTarget.cmake")
add_version_info_target(NAME VInfoCPP
  NAMESPACE QrX WdZ
  # GIT_WORK_TREE ${PROJECT_SOURCE_DIR} # uncomment if project is a git repo
)
add_executable(${PROJECT_NAME} main.cpp)
target_link_libraries(${PROJECT_NAME} PRIVATE VInfoCPP)
install(TARGETS ${PROJECT_NAME} DESTINATION .)
```

```cpp
// main.cpp
#include <iostream>
#include "VInfoCPP/VersionInfo.hpp"
int main() {
  std::cout << QrX::WdZ::VersionSummary << std::endl;
  return 0;
}
```

## Usage - Minimum Reproducible Example (C)

```cmake
# CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(HelloVersion VERSION 1.2.3 LANGUAGES C)
include("3rd/CMakeVersionInfoTarget/VersionInfoTarget.cmake")
add_version_info_target(NAME VInfoC LANGUAGE C
  NAMESPACE QrX WdZ
  # GIT_WORK_TREE ${PROJECT_SOURCE_DIR}
)
add_executable(${PROJECT_NAME} main.c)
target_link_libraries(${PROJECT_NAME} PRIVATE VInfoC)
install(TARGETS ${PROJECT_NAME} DESTINATION .)
```

```cpp
// main.c
#include <stdio.h>
#include "VInfoC/VersionInfo.h"

int main() {
  printf("%s\n", QrX_WdZ_VersionSummary);
  return 0;
}
```

## Advice

### Building an Executable

If you are building an executable, it is recommended to use
`CMakeVersionInfoTarget` to generate a command-line display whenever a
user issues `<program-name> --version` on the command-line.

## Why doesn't the project info include a timestamp?

This module attempts to support reproducible builds. A reproducible build
produces exactly the same binary file every time it is run on the same source
code. To serve this goal, this module explicitly does **NOT** insert ephemeral
information like: user names, system names, or compile time-stamps, as these
things would change the version info files every time the build was re-run on a
different machine or at a different time. This is why this module only inserts
committer name, commit time, and relevant aspects of the build system such as
the architecture and compiler (which would affect the binary anyway).

No tests have been done to confirm there are no other reproducibility issues
introduced by this module.

## Git Submodules

This is a perfect use-case for Git submodules!

To add this project as a git submodule to your project:

1. `cd` to your project directory

2. add the submodule

   ```sh
   # git submodule add "<url-of-submodule-repo>" "<subdir-to-store-submodule>"
   git submodule add "https://github.com/skaravos/CMakeVersionInfoTarget.git" "3rd/CMakeVersionInfoTarget"
   ```

   This will create a subdirectory (`3rd/CMakeVersionInfoTarget`) that contains
   all the files required to run this cmake module.
