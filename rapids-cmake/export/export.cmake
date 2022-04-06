#=============================================================================
# Copyright (c) 2021, NVIDIA CORPORATION.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#=============================================================================
include_guard(GLOBAL)

#[=======================================================================[.rst:
rapids_export
---------------------

.. versionadded:: v21.06.00

Generate a projects -Config.cmake module and all related information

.. code-block:: cmake

  rapids_export( (BUILD|INSTALL) <project_name>
      EXPORT_SET <export_set>
      [ GLOBAL_TARGETS <targets...> ]
      [ VERSION <X.Y.Z> ]
      [ NAMESPACE <name_space> ]
      [ DOCUMENTATION <doc_variable> ]
      [ FINAL_CODE_BLOCK <code_block_variable> ]
      [ LANGUAGES <langs...> ]
      )

The :cmake:command:`rapids_export` function allow projects to easily generate a fully
correct build and install tree `Project-Config.cmake` module including any necessary
calls to :cmake:command:`find_dependency`, or :cmake:command:`CPMFindPackage`.

.. note::
  :cmake:command:`rapids_export` always installs to `lib` and doesn't use GNUInstallDirs

  The files generated by :cmake:command:`rapids_export` are completly standalone
  and don't require the consuming package to use `rapids-cmake`

``project_name``
  Name of the project, to be used by consumers when using `find_package`

``GLOBAL_TARGETS``
  Explicitly list what targets should be made globally visibile to
  the consuming project.

``VERSION``
  Explicitly list the version of the package being exported. By
  default :cmake:command:`rapids_export` uses the version specified by the
  root level :cmake:command:`project <cmake:command:project>` call. If no version has
  been specified either way or `OFF` is provided as the `VERSION` value, no version
  compatibility checks will be generated.

  Depending on the version string different compatibility modes will be used.

    +------------------+---------------------+
    | Version String   | Compatiblity Type   |
    +==================+=====================+
    | None             | No checks perfomed  |
    +------------------+---------------------+
    | X                | SameMajorVersion    |
    +------------------+---------------------+
    | X.Y              | SameMinorVersion    |
    +------------------+---------------------+
    | X.Y.Z            | SameMinorVersion    |
    +------------------+---------------------+

.. note::
    It can be useful to explicitly specify a version string when generating
    export rules for a sub-component of alarger project, or an external
    project that doesn't have export rules.

``NAMESPACE``
  Optional value to specify what namespace all targets from the
  EXPORT_SET will be placed into. When provided must match the pattern
  of `<name>::`.
  If not provided all targets will be placed in the `<project_name>::`
  namespace

  Note: When exporting with `BUILD` type, only `GLOBAL_TARGETS` will
  be placed in the namespace.

``DOCUMENTATION``
  Optional value of the variable that holds the documentation
  for this config file.

  Note: This requires the documentation variable instead of the contents
  so we can handle having CMake code inside the documentation

``FINAL_CODE_BLOCK``
  Optional value of the variable that holds a string of code that will
  be executed at the last step of this config file.

  Note: This requires the code block variable instead of the contents
  so that we can properly insert CMake code

``LANGUAGES``
  Non default languages, such as CUDA that are required by consumers
  of your package. This makes sure all consumers properly setup these
  languages correctly.

  This is required as CMake's :cmake:command:`enable_language <cmake:command:enable_language>`
  only supports enabling languages for the current directory scope, and
  doesn't support being called from within functions. Marking languages
  here overcomes these limitations and makes it possible for packages included
  via `CPM` to enable languages.


Example on how to properly use :cmake:command:`rapids_export`:

.. code-block:: cmake

  ...

  add_library(example STATIC source.cu)
  target_compile_features(example PUBLIC $<BUILD_INTERFACE:cuda_std_17>)

  rapids_cmake_install_lib_dir(lib_dir)
  install(TARGETS example
          DESTINATION ${lib_dir}
          EXPORT example-targets
          )

  set(doc_string [=[Provide targets for the example library.]=])

  set(code_string [=[ message(STATUS "hi from example-config")]=])

   rapids_export(INSTALL example
      EXPORT_SET example-targets
      GLOBAL_TARGETS example # Need to list all targets from `install(TARGETS`
      NAMESPACE example::
      DOCUMENTATION doc_string
      FINAL_CODE_BLOCK code_string
      )

  rapids_export(BUILD example
      EXPORT_SET example-targets
      GLOBAL_TARGETS example # Need to list all targets from `install(TARGETS`
      # CUDA language support is a build detail only, as target_compile_features
      # guards the language behind `BUILD_INTERFACE` generator expression
      LANGUAGES CUDA
      NAMESPACE example::
      DOCUMENTATION doc_string
      FINAL_CODE_BLOCK code_string
      )


#]=======================================================================]
# cmake-lint: disable=R0912,R0915,W0105
function(rapids_export type project_name)
  include(CMakePackageConfigHelpers)

  list(APPEND CMAKE_MESSAGE_CONTEXT "rapids.export.export")
  string(TOLOWER ${type} type)

  set(options "")
  set(one_value EXPORT_SET VERSION NAMESPACE DOCUMENTATION FINAL_CODE_BLOCK)
  set(multi_value GLOBAL_TARGETS LANGUAGES)
  cmake_parse_arguments(RAPIDS "${options}" "${one_value}" "${multi_value}" ${ARGN})

  set(rapids_version_set ON)
  if(DEFINED RAPIDS_VERSION AND NOT RAPIDS_VERSION)
    # We need to capture `VERSION OFF` so we need to make sure it has an off value, and not just
    # undefined
    set(rapids_version_set OFF)
    unset(RAPIDS_VERSION) # unset this so we don't export a version value of `OFF`
  elseif(NOT DEFINED RAPIDS_VERSION AND NOT DEFINED PROJECT_VERSION)
    set(rapids_version_set OFF)
  elseif(DEFINED PROJECT_VERSION AND NOT DEFINED RAPIDS_VERSION)
    # Choose the project version when an explicit version isn't provided
    set(RAPIDS_VERSION "${PROJECT_VERSION}")
  endif()

  if(rapids_version_set)
    include("${rapids-cmake-dir}/export/detail/parse_version.cmake")
    rapids_export_parse_version(${RAPIDS_VERSION} rapids_orig rapids_project_version)
  endif()

  set(RAPIDS_PROJECT_NAMESPACE "${project_name}::")
  if(DEFINED RAPIDS_NAMESPACE)
    set(RAPIDS_PROJECT_NAMESPACE ${RAPIDS_NAMESPACE})
  endif()

  set(RAPIDS_PROJECT_DOCUMENTATION "Generated ${project_name}-config module")
  if(DEFINED RAPIDS_DOCUMENTATION)
    if(NOT DEFINED ${RAPIDS_DOCUMENTATION})
      message(FATAL_ERROR "DOCUMENTATION variable `${RAPIDS_DOCUMENTATION}` doesn't exist")
    endif()
    set(RAPIDS_PROJECT_DOCUMENTATION "${${RAPIDS_DOCUMENTATION}}")
  endif()

  if(DEFINED RAPIDS_FINAL_CODE_BLOCK)
    if(NOT DEFINED ${RAPIDS_FINAL_CODE_BLOCK})
      message(FATAL_ERROR "FINAL_CODE_BLOCK variable `${RAPIDS_FINAL_CODE_BLOCK}` doesn't exist")
    endif()
    set(RAPIDS_PROJECT_FINAL_CODE_BLOCK "${${RAPIDS_FINAL_CODE_BLOCK}}")
  endif()

  # Write configuration and version files
  string(TOLOWER ${project_name} project_name)
  string(TOUPPER ${project_name} project_name_uppercase)
  if(type STREQUAL "install")
    include("${rapids-cmake-dir}/cmake/install_lib_dir.cmake")
    rapids_cmake_install_lib_dir(install_location)
    set(install_location "${install_location}/cmake/${project_name}")

    set(scratch_dir "${PROJECT_BINARY_DIR}/rapids-cmake/${project_name}/export")

    configure_package_config_file("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/template/config.cmake.in"
                                  "${scratch_dir}/${project_name}-config.cmake"
                                  INSTALL_DESTINATION "${install_location}")

    if(rapids_version_set)
      write_basic_package_version_file(
        "${scratch_dir}/${project_name}-config-version.cmake" VERSION ${rapids_project_version}
        COMPATIBILITY ${rapids_project_version_compat})
    endif()

    install(EXPORT ${RAPIDS_EXPORT_SET} FILE ${project_name}-targets.cmake
            NAMESPACE ${RAPIDS_PROJECT_NAMESPACE} DESTINATION "${install_location}")

    if(TARGET rapids_export_install_${RAPIDS_EXPORT_SET})
      include("${rapids-cmake-dir}/export/write_dependencies.cmake")
      set(destination "${scratch_dir}/${project_name}-dependencies.cmake")
      rapids_export_write_dependencies(INSTALL ${RAPIDS_EXPORT_SET} "${destination}")
    endif()

    if(DEFINED RAPIDS_LANGUAGES)
      include("${rapids-cmake-dir}/export/write_language.cmake")
      foreach(lang IN LISTS RAPIDS_LANGUAGES)
        set(destination "${scratch_dir}/${project_name}-${lang}-language.cmake")
        rapids_export_write_language(INSTALL ${lang} "${destination}")
      endforeach()
    endif()

    # Install everything we have generated
    install(DIRECTORY "${scratch_dir}/" DESTINATION "${install_location}")

  else()
    set(install_location "${PROJECT_BINARY_DIR}")
    configure_package_config_file("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/template/config.cmake.in"
                                  "${install_location}/${project_name}-config.cmake"
                                  INSTALL_DESTINATION "${install_location}")

    if(rapids_version_set)
      write_basic_package_version_file(
        "${install_location}/${project_name}-config-version.cmake" VERSION ${rapids_project_version}
        COMPATIBILITY ${rapids_project_version_compat})
    endif()

    export(EXPORT ${RAPIDS_EXPORT_SET} NAMESPACE ${RAPIDS_PROJECT_NAMESPACE}
           FILE "${install_location}/${project_name}-targets.cmake")

    if(TARGET rapids_export_build_${RAPIDS_EXPORT_SET})
      include("${rapids-cmake-dir}/export/write_dependencies.cmake")
      rapids_export_write_dependencies(BUILD ${RAPIDS_EXPORT_SET}
                                       "${install_location}/${project_name}-dependencies.cmake")
    endif()

    if(DEFINED RAPIDS_LANGUAGES)
      include("${rapids-cmake-dir}/export/write_language.cmake")
      foreach(lang IN LISTS RAPIDS_LANGUAGES)
        rapids_export_write_language(BUILD ${lang}
                                     "${install_location}/${project_name}-${lang}-language.cmake")
      endforeach()
    endif()

  endif()

endfunction()
