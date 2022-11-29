cmake_minimum_required(VERSION 3.10)

set(_current_function_list_dir ${CMAKE_CURRENT_LIST_DIR})

#[=[
  adds two cmake targets:
    1. a C/C++ static library target that contains project version info
    2. [internal] a cmake custom target that queries version info at build time

  add_version_info_target(NAME <unique_target_name>
                      [LINK_TO targets...]
                      [NAMESPACE namespaces...]
                      [LANGUAGE language]
                      [GIT_WORK_TREE <git_work_tree>]
                      [PROJECT_NAME <name>]
                      [PROJECT_VERSION <version>]
                    )

  NAME <unique_target_name>  (required)
    provide the name of a non-existing target

  LINK_TO targets... (optional)
    if provided, this library will be automatically linked to all given targets

  NAMESPACE namespaces... (optional; default="VersionInfo")
    if provided, the variables contained in the generated headers files will be
    enclosed in a namespace (C++) or have an underscore_separated prefix (C).

      ex. (LANGUAGE=C++)
        # CMakeLists.txt
        add_version_info_target(NAME FooVersion NAMESPACE Abc XyZ LANGUAGE CXX)
        // 'VersionInfo.hpp'
        namespace Abc { namespace XyZ {
          extern const char* const ProjectName;
          ...
        }}

      ex. (LANGUAGE=C)
        # CMakeLists.txt
        add_version_info_target(NAME FooVersion NAMESPACE Abc XyZ LANGUAGE C)
        // 'VersionInfo.h'
        extern const char* const Abc_XyZ_ProjectName;
        ...

  LANGUAGE language (optional;default=CXX)
    specify the language used for the header and source files (C or CXX)

  GIT_WORK_TREE (optional)
    if provided, git commit information will be queried at build-time
    NOTE: this option requires cmake to be able to find_package(Git)

  PROJECT_NAME <name>  (optional; default=name of current project)
    if provided, the target will use the given name instead of the current
    project name.

  PROJECT_VERSION <version>  (optional; default=version of current project)
    if provided, the target will use the given version instead of the current
    project version.
    NOTE: must be provided in the form <major[.minor[.patch[[.-]tweak]]>
    NOTE: the 'tweak' version can be separated using either a period or a hyphen
          e.g. both 1.0.1.1 and 1.0.1-rev1 are valid versions

#]=]
function(add_version_info_target)

  # --- parse arguments

  set(_options)
  set(_singleargs NAME LANGUAGE GIT_WORK_TREE PROJECT_NAME PROJECT_VERSION)
  set(_multiargs LINK_TO NAMESPACE)
  cmake_parse_arguments(
    PARSE_ARGV 0
    arg
    "${_options}"
    "${_singleargs}"
    "${_multiargs}"
  )

  message(STATUS "add_version_info_target('${arg_NAME}')")

  foreach(_arg IN LISTS arg_UNPARSED_ARGUMENTS)
    message(WARNING "Unparsed argument: ${_arg}")
  endforeach()

  # --- validate arguments

  if (NOT arg_NAME)
    message(FATAL_ERROR "NAME parameter is required")
  endif()

  if (TARGET ${arg_NAME})
    message(WARNING "A target with this NAME[${arg_NAME}] already exists")
  endif()

  foreach(_ns ${arg_NAMESPACE})
    if(NOT _ns MATCHES "^[_a-zA-Z][_a-zA-Z0-9]*$")
      message(FATAL_ERROR "Provided NAMESPACE [${_ns}] isn't valid in C/C++")
    endif()
  endforeach()

  foreach(_tgt ${arg_LINK_TO})
    if (NOT TARGET ${_tgt})
      message(FATAL_ERROR "LINK_TO parameter invalid: [${_tgt}] isn't a target")
    endif()
  endforeach()

  if (arg_GIT_WORK_TREE)
    if (NOT EXISTS "${arg_GIT_WORK_TREE}")
      message(FATAL_ERROR "Provided GIT_WORK_TREE does not exist")
    endif()
    find_package(Git REQUIRED QUIET)
    if (NOT GIT_EXECUTABLE)
      message(FATAL_ERROR "Parameter GIT_WORK_TREE provided but Git not found")
    endif()
    execute_process(
      COMMAND ${GIT_EXECUTABLE} rev-parse HEAD
      WORKING_DIRECTORY ${arg_GIT_WORK_TREE}
      RESULT_VARIABLE _git_result
      OUTPUT_QUIET
      ERROR_QUIET
    )
    if (NOT _git_result EQUAL 0)
      message(FATAL_ERROR "Provided GIT_WORK_TREE is not a git repository")
    endif()
  endif()

  if (arg_LANGUAGE AND (NOT "${arg_LANGUAGE}" MATCHES [[^(C|CXX|C\+\+)$]]))
    message(FATAL_ERROR "Parameter LANGUAGE must be one of: C or CXX")
  endif()

  # --- determine language to use

  if (${arg_LANGUAGE} STREQUAL "C")
    if (NOT CMAKE_C_COMPILER)
      message(FATAL_ERROR "LANGUAGE C specified but no C compiler found")
    endif()
    set(_language "C")
    set(_hdr_ext  "h")
    set(_src_ext  "c")
    set(_compiler_id      ${CMAKE_C_COMPILER_ID})
    set(_compiler_version ${CMAKE_C_COMPILER_VERSION})
  else()
    if (NOT CMAKE_CXX_COMPILER)
      message(FATAL_ERROR "LANGUAGE CXX specified but no CXX compiler found")
    endif()
    set(_language "CXX")
    set(_hdr_ext  "hpp")
    set(_src_ext  "cpp")
    set(_compiler_id      ${CMAKE_CXX_COMPILER_ID})
    set(_compiler_version ${CMAKE_CXX_COMPILER_VERSION})
  endif()

  # --- set internal variables

  set(_vinfo_templates_dir "${_current_function_list_dir}/templates")
  set(_vinfo_src_in    "${_vinfo_templates_dir}/VersionInfo.${_src_ext}.in")
  set(_vinfo_hdr_in    "${_vinfo_templates_dir}/VersionInfo.${_hdr_ext}.in")

  set(_vinfo_workspace "${CMAKE_CURRENT_BINARY_DIR}/${arg_NAME}")
  set(_vinfo_src       "${_vinfo_workspace}/VersionInfo.${_src_ext}")
  set(_vinfo_hdr       "${_vinfo_workspace}/include/${arg_NAME}/VersionInfo.${_hdr_ext}")

  set(_vinfo_query_cmake "${_vinfo_workspace}/VersionInfoQuery.cmake")
  set(_query_targetname  "${arg_NAME}_QueryVersionInfo")

  # --- determine version to use

  if (arg_PROJECT_VERSION)
    string(REGEX MATCH [[([0-9]+)(\.([0-9]+)(\.([0-9]+)([.-]([A-Za-z0-9]+))?)?)?]]
           _matched "${arg_PROJECT_VERSION}")
    set(_version       "${CMAKE_MATCH_0}")
    set(_version_major "${CMAKE_MATCH_1}")
    set(_version_minor "${CMAKE_MATCH_3}")
    set(_version_patch "${CMAKE_MATCH_5}")
    set(_version_tweak "${CMAKE_MATCH_7}")
  else()
    set(_version       ${PROJECT_VERSION})
    set(_version_major ${PROJECT_VERSION_MAJOR})
    set(_version_minor ${PROJECT_VERSION_MINOR})
    set(_version_patch ${PROJECT_VERSION_PATCH})
    set(_version_tweak ${PROJECT_VERSION_TWEAK})
  endif()

  # --- determine project name

  if (arg_PROJECT_NAME)
    set(_project_name "${arg_PROJECT_NAME}")
  else()
    set(_project_name "${PROJECT_NAME}")
  endif()

  # --- setup namespace variables for configuring Version.h.in

  if (DEFINED arg_NAMESPACE)
    set(_namespace ${arg_NAMESPACE})
  else()
    set(_namespace "VersionInfo") # default if user didnt give an explicit value
  endif()

  if (_namespace)
    # for the first given namespace
    list(POP_FRONT _namespace _ns1)
    set(_namespace_access_prefix "${_ns1}_")
    set(_namespace_scope_opening "namespace ${_ns1} {")
    set(_namespace_scope_closing "} /* namespace ${_ns1} */")
    set(_namespace_scope_resolve "${_ns1}::")

    # for each additional namespace in the argument list (if-any)
    foreach(_ns ${_namespace})
      set(_namespace_access_prefix "${_namespace_access_prefix}${_ns}_")
      set(_namespace_scope_opening "${_namespace_scope_opening} namespace ${_ns} {")
      set(_namespace_scope_closing "${_namespace_scope_closing} } /* namespace ${_ns} */")
      set(_namespace_scope_resolve "${_namespace_scope_resolve}${_ns}::")
    endforeach()
  endif()

  # --- make some workspace directories

  file(MAKE_DIRECTORY "${_vinfo_workspace}")
  file(MAKE_DIRECTORY "${_vinfo_workspace}/include/${arg_NAME}")

  # --- generate placeholder files

  # create VersionInfoQuery.cmake
  __create_vinfo_query_cmake(${_vinfo_query_cmake})

  # we use file(APPEND ...) here to generate a temporary copies of the source
  # and header files to prevent CMake freaking out about 'file does not exist'
  # NOTE: when the custom QueryVersionInfo target is built, the Version.cmake
  #       script is invoked which will create the real copies of the files
  file(APPEND ${_vinfo_hdr} "")
  file(APPEND ${_vinfo_src} "")

  # --- create query target

  add_custom_target(${_query_targetname} ALL
    BYPRODUCTS
      ${_vinfo_hdr}
      ${_vinfo_src}
    COMMAND
      ${CMAKE_COMMAND}
      -D_TARGET_NAME=${arg_NAME}
      -D_PROJECT_NAME=${_project_name}
      -D_PROJECT_VERSION=${_version}
      -D_PROJECT_VERSION_MAJOR=${_version_major}
      -D_PROJECT_VERSION_MINOR=${_version_minor}
      -D_PROJECT_VERSION_PATCH=${_version_patch}
      -D_PROJECT_VERSION_TWEAK=${_version_tweak}
      -D_NAMESPACE_ACCESS_PREFIX=${_namespace_access_prefix}
      -D_NAMESPACE_SCOPE_OPENING=${_namespace_scope_opening}
      -D_NAMESPACE_SCOPE_CLOSING=${_namespace_scope_closing}
      -D_NAMESPACE_SCOPE_RESOLVE=${_namespace_scope_resolve}
      -D_VINFO_HDR_IN=${_vinfo_hdr_in}
      -D_VINFO_HDR=${_vinfo_hdr}
      -D_VINFO_SRC_IN=${_vinfo_src_in}
      -D_VINFO_SRC=${_vinfo_src}
      -D_GIT_WORK_TREE=${arg_GIT_WORK_TREE}
      -D_LANGUAGE=${_language}
      -D_COMPILER_ID=${_compiler_id}
      -D_COMPILER_VERSION=${_compiler_version}
      -D_CMAKE_SYSTEM_PROCESSOR=${CMAKE_SYSTEM_PROCESSOR}
      -D_BUILD_TYPE=$<CONFIG>
      -P ${_vinfo_query_cmake}
    COMMENT
      "Querying project version information and writing VersionInfo files..."
    DEPENDS
      ${_vinfo_hdr_in}
      ${_vinfo_src_in}
      ${_vinfo_query_cmake}
  )

  # --- create library target

  add_library(${arg_NAME} STATIC)

  target_sources(${arg_NAME} PRIVATE ${_vinfo_hdr} ${_vinfo_src})

  target_include_directories(${arg_NAME}
    # NOTE: set both INTERFACE & PRIVATE here because PUBLIC isn't working???
    INTERFACE
      # including both level of include directories gives users a choice between
      #    #include "VersionInfo.h"
      #    #include "<TargetName>/VersionInfo.h"
      #
      "${_vinfo_workspace}/include"
      "${_vinfo_workspace}/include/${arg_NAME}"
    PRIVATE
      "${_vinfo_workspace}/include"
      "${_vinfo_workspace}/include/${arg_NAME}"
  )

  set_target_properties(${arg_NAME}
    PROPERTIES
      LINKER_LANGUAGE ${_language}
  )

  # gotta make sure it depends on the query target so that the query runs first!
  add_dependencies(${arg_NAME} ${_query_targetname})

  # --- link the target to any provided user targets

  foreach(_tgt ${arg_LINK_TO})
    message(STATUS "  privately linking target ${_tgt} to ${arg_NAME}")
    target_link_libraries(${_tgt} PRIVATE ${arg_NAME})
  endforeach()

  # --- done!

  message(STATUS "add_version_info_target('${arg_NAME}') - success")

endfunction()


function(__create_vinfo_query_cmake target_file_path)
  file(WRITE ${target_file_path} [==========[
# This file is auto-generated by VersionInfoTarget.cmake, do not edit.

# This file configures the VersionInfo header and source files with system
# and project information such as:
#   Project Name, Compiler version & ID, System Processor Arch, Config Type
#
# It also uses the git executable to determine relevant repository info:
#   Dirty Status, Commit Date, Commit Hash, User Name, User Email
#
# This module is NOT designed to be directly included in a CMakeLists.txt file.
#
# It is called as a COMMAND in a custom_target.
# Because the information is inserted into the Version header at the time this
# file is parsed, the goal is to have this file be parsed right before the main
# program executable is compiled. Calling this file from a custom_target ensures
# that we can configure the dependencies so that it gets run at compile time

if (_GIT_WORK_TREE)
  find_package(Git REQUIRED QUIET)
  # --- Git Status (is it dirty?)
  execute_process(
    COMMAND ${GIT_EXECUTABLE} status --porcelain --untracked-files=no
    WORKING_DIRECTORY ${_GIT_WORK_TREE}
    OUTPUT_VARIABLE _git_status_output
  )
  if (_git_status_output)
    set(_GIT_UNCOMMITTED_CHANGES "1")
    message(WARNING
    "\nGit repository is dirty (uncommitted changes); do not release this version"
    )
  else()
    set(_GIT_UNCOMMITTED_CHANGES "0")
  endif()
  # --- Git Revision Hash
  execute_process(
    COMMAND ${GIT_EXECUTABLE} rev-parse HEAD
    WORKING_DIRECTORY ${_GIT_WORK_TREE}
    OUTPUT_VARIABLE _GIT_COMMIT_HASH
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  # --- Git Commit Date
  execute_process(
    COMMAND ${GIT_EXECUTABLE} show -s --format=%cd HEAD
    WORKING_DIRECTORY ${_GIT_WORK_TREE}
    OUTPUT_VARIABLE _GIT_COMMIT_DATE
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  # --- Git User Name
  execute_process(
    COMMAND ${GIT_EXECUTABLE} show -s --format=%cn
    WORKING_DIRECTORY ${_GIT_WORK_TREE}
    OUTPUT_VARIABLE _GIT_USER_NAME
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  # --- Git User Email
  execute_process(
    COMMAND ${GIT_EXECUTABLE} show -s --format=%ce
    WORKING_DIRECTORY ${_GIT_WORK_TREE}
    OUTPUT_VARIABLE _GIT_USER_EMAIL
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )

  set(_GIT_VARIABLE_DECLARATIONS_CXX "
extern const bool        GitUncommittedChanges;
extern const char* const GitCommitHash;
extern const char* const GitCommitDate;
extern const char* const GitUserName;
extern const char* const GitUserEmail;
")

  set(_GIT_VARIABLE_DECLARATIONS_C "
extern const int         ${_NAMESPACE_ACCESS_PREFIX}GitUncommittedChanges; // 0 - false, 1 - true
extern const char* const ${_NAMESPACE_ACCESS_PREFIX}GitCommitHash;
extern const char* const ${_NAMESPACE_ACCESS_PREFIX}GitCommitDate;
extern const char* const ${_NAMESPACE_ACCESS_PREFIX}GitUserName;
extern const char* const ${_NAMESPACE_ACCESS_PREFIX}GitUserEmail;
")

  set(_GIT_VARIABLE_DEFINITIONS_CXX "
const bool        GitUncommittedChanges = ${_GIT_UNCOMMITTED_CHANGES};
const char* const GitCommitHash = \"${_GIT_COMMIT_HASH}\";
const char* const GitCommitDate = \"${_GIT_COMMIT_DATE}\";
const char* const GitUserName   = \"${_GIT_USER_NAME}\";
const char* const GitUserEmail  = \"${_GIT_USER_EMAIL}\";
")

  set(_GIT_VARIABLE_DEFINITIONS_C "
const int         ${_NAMESPACE_ACCESS_PREFIX}GitUncommittedChanges = ${_GIT_UNCOMMITTED_CHANGES};
const char* const ${_NAMESPACE_ACCESS_PREFIX}GitCommitHash = \"${_GIT_COMMIT_HASH}\";
const char* const ${_NAMESPACE_ACCESS_PREFIX}GitCommitDate = \"${_GIT_COMMIT_DATE}\";
const char* const ${_NAMESPACE_ACCESS_PREFIX}GitUserName   = \"${_GIT_USER_NAME}\";
const char* const ${_NAMESPACE_ACCESS_PREFIX}GitUserEmail  = \"${_GIT_USER_EMAIL}\";
")

  if (_GIT_UNCOMMITTED_CHANGES)
    set(_GIT_UNCOMMITTED_CHANGES_STRING " (uncommitted changes)")
  endif()
  set(_GIT_PRINTOUT_SUMMARY
"\"\\nCommitHash: ${_GIT_COMMIT_HASH}${_GIT_UNCOMMITTED_CHANGES_STRING}\"
\"\\nCommitUser: ${_GIT_USER_NAME} (${_GIT_USER_EMAIL})\"
\"\\nCommitDate: ${_GIT_COMMIT_DATE}\""
)


endif(_GIT_WORK_TREE)

# --- C++ specific features

if (_BUILD_TYPE)
  set(_BUILD_TYPE_SUFFIX "-${_BUILD_TYPE}")
endif()

set(_AUTOGENERATED_FILE_WARNING
  "// This file was autogenerated by 'VersionInfoTarget.cmake', do not edit"
)

# --- Configure Version header

configure_file(
  ${_VINFO_HDR_IN}
  ${_VINFO_HDR}
  @ONLY
)

# --- Configure Version header

configure_file(
  ${_VINFO_SRC_IN}
  ${_VINFO_SRC}
  @ONLY
)
]==========]
  )
endfunction() # __create_vinfo_query_cmake
