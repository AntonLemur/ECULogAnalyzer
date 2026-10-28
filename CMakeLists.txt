cmake_minimum_required(VERSION 3.16)

project(ECULogAnalyzer VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Поиск необходимых модулей Qt
find_package(Qt6 6.10.3 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    Graphs
)

qt_standard_project_setup(REQUIRES 6.10.3)

# Исходный код C++
set(PROJECT_SOURCES
    main.cpp
    logparser.h
    logparser.cpp
)

# Описание исполняемого файла и ресурсов QML
qt_add_executable(ECULogAnalyzer ${PROJECT_SOURCES})

qt_add_qml_module(ECULogAnalyzer
    URI ECULogAnalyzer
    VERSION 1.0
    QML_FILES
        Main.qml
)

# Настройки линковки для Windows (скрытие консоли в Release)
set_target_properties(ECULogAnalyzer PROPERTIES
    WIN32_EXECUTABLE ON
    MACOSX_BUNDLE ON
)

# Подключение библиотек
target_link_libraries(ECULogAnalyzer PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::Graphs
)
