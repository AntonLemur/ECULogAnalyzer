import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtGraphs // Импортируем новый модуль 3D графики
import ECULogAnalyzer

ApplicationWindow {
    id: window
    width: 1024
    height: 768
    visible: true
    title: qsTr("Авто-Анализатор логов ЭБУ (turboquattro)")

    // 1. Подключаем наш переработанный C++ парсер
    LogParser {
        id: logParser

        // Сигнал об ошибке
        onErrorOccurred: (msg) => {
            errorLabel.text = msg
            errorDialog.open()
        }

        // Обработчик изменения индекса (для кликов и внешних изменений)
        // Теперь он автоматически синхронизирует ListView с C++
        onActiveLogIndexChanged: {
            logsListView.currentIndex = logParser.activeLogIndex
            // А саму прокрутку откладываем на один квант времени,
            // чтобы элемент успел физически занять свое место в интерфейсе
            // Qt.callLater(function() {
            //     logsListView.positionViewAtIndex(logParser.activeLogIndex, ListView.Contain)
            // })
        }

        // При успешной загрузке лога — обновляем списки осей в ComboBox
        onLoadedLogsChanged: {
            // Вычисляем индекс сразу
            var lastIndex = logParser.loadedLogs.length - 1
            if (lastIndex < 0) return;

            // Передаем индекс в C++ (это можно сделать сразу)
            logParser.setActiveLogIndex(lastIndex)

            // Откладываем обновление интерфейса до тех пор, пока ListView не создаст новый элемент
            // Qt.callLater(function() {
            //     // Теперь ListView знает о существовании lastIndex и успешно выделит его
                var headers = logParser.getHeaders(lastIndex)
                xAxisCombo.model = headers
                yAxisCombo.model = headers
                zAxisCombo.model = headers

                surfaceSeries.selectedPoint = Qt.point(-1, -1)

                var rpmIdx = headers.indexOf("RPM")
                var thrIdx = headers.indexOf("THR")
                var uozIdx = headers.indexOf("UOZ")

                if (rpmIdx !== -1) xAxisCombo.currentIndex = rpmIdx
                if (thrIdx !== -1) yAxisCombo.currentIndex = thrIdx
                if (uozIdx !== -1) zAxisCombo.currentIndex = uozIdx

                update3DGraph()
            // })
        }
    }

    // Функция обновления данных на 3D сцене
    function update3DGraph() {
        if (logParser.loadedLogs.length === 0) return;

        graph3D.axisX.title = xAxisCombo.currentText
        graph3D.axisZ.title = yAxisCombo.currentText
        graph3D.axisY.title = zAxisCombo.currentText

        var logIndex = logParser.getActiveLogIndex()

        logParser.generate3DMatrix(
            surfaceSeries,
            logIndex,
            xAxisCombo.currentText,
            yAxisCombo.currentText,
            zAxisCombo.currentText,
            1
        )

        // ХАК ДЛЯ СЕТКИ: Извлекаем реальные экстремумы и жестко фиксируем ось Y
        var minY = logParser.getCurrentMinY()
        var maxY = logParser.getCurrentMaxY()

        // Добавляем небольшой отступ в 5%, чтобы график не упирался в "потолок" и "пол"
        var padding = (maxY - minY) * 0.05
        if (padding === 0) padding = 1.0 // Защита от деления на ноль, если карта плоская

        graph3D.axisY.min = minY - padding
        graph3D.axisY.max = maxY + padding
        // graph3D.axisY.segmentCount = 5 // Четкое количество делений сетки
    }

    function applyCustomFormula() {
        var row = surfaceSeries.selectedPoint.y
        var col = surfaceSeries.selectedPoint.x // Наша рабочая коррекция оси Z

        var formulaStr = formulaField.text.trim()
        if (formulaStr === "") return;

        // 1. Вызываем безопасный C++ парсер формул
        logParser.applyFormula(row, col, formulaStr)

        // 2. Мгновенно обновляем геометрию сетки на экране
        logParser.updateActiveSeries(surfaceSeries)

        // 3. Обновляем текстовое поле маркера новым значением
        var newVal = logParser.getMatrixValue(row, col)
        markerLabel.text =
            xAxisCombo.currentText + " (Индекс X: " + row + ") | " +
            yAxisCombo.currentText + " (Индекс Z: " + col + ") | " +
            zAxisCombo.currentText + " = " + newVal.toFixed(2)
    }

    // 1. Создаем общую функцию скролла
    // function syncComboBoxPopup(comboBox) {
    //     var list = comboBox.popup.contentItem;
    //     if (list && typeof list.positionViewAtIndex === "function") {
    //         list.positionViewAtIndex(comboBox.currentIndex, ListView.Contain);
    //     }
    // }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ================= ЛЕВАЯ ПАНЕЛЬ УПРАВЛЕНИЯ =================
        Rectangle {
            Layout.preferredWidth: 280
            Layout.fillHeight: true
            color: "#f5f5f5"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 15

                Button {
                    Layout.fillWidth: true
                    text: qsTr("Открыть файл лога (.csv)")
                    onClicked: fileDialog.open()
                }

                // --- СПИСОК ЗАГРУЖЕННЫХ ЛОГОВ (Пункт 3 ТЗ) ---
                Label {
                    text: qsTr("Загруженные логи (до 10 шт):")
                    font.bold: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    color: "#ffffff"
                    border.color: "#bdc3c7"
                    border.width: 1
                    radius: 4

                    ListView {
                        id: logsListView
                        anchors.fill: parent
                        anchors.margins: 5
                        clip: true
                        // Связываем модель напрямую со списком имен m_loadedLogNames из C++
                        model: logParser.loadedLogs
                        focus: true

                        delegate: ItemDelegate {
                            width: logsListView.width
                            height: 30

                            // Используем встроенный внутренний флаг элемента списка
                            highlighted: ListView.isCurrentItem

                            contentItem: Text {
                                text: modelData
                                font.bold: index === logParser.activeLogIndex
                                color: index === logParser.activeLogIndex ? "#2980b9" : "#2c3e50"
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                // Сравниваем индекс конкретного элемента с текущим выбранным в С++
                                color: index === logParser.activeLogIndex ? "lightsteelblue" : "transparent"
                                radius: 5
                            }

                            onClicked: {
                                logParser.setActiveLogIndex(index)
                                // logsListView.currentIndex = index // Явно обновляем индекс списка
                                // Динамически обновляем ComboBox заголовками выбранного файла
                                var headers = logParser.getHeaders(index)
                                xAxisCombo.model = headers
                                yAxisCombo.model = headers
                                zAxisCombo.model = headers

                                // Перестраиваем 3D-график
                                update3DGraph()
                            }
                        }

                        // Декларативный скролл: список сам следит за своим currentIndex.
                        // Этот обработчик движок QML вызывает ровно тогда, когда внутренний layout уже готов.
                        onCurrentIndexChanged: logsListView.positionViewAtIndex(logParser.activeLogIndex, ListView.Contain)
                    }
                }

                Label { text: qsTr("Ось X (Строки):") }
                ComboBox {
                    id: xAxisCombo
                    Layout.fillWidth: true
                    // Явно объявляем пустой массив, который заполнится из C++
                    model: []
                    onActivated: update3DGraph()

                    // Решение: явно задаем стандартный делегат с фиксом подсветки
                    delegate: ItemDelegate {
                        width: xAxisCombo.width
                        text: modelData
                        hoverEnabled: true

                        // Принудительно подсвечиваем элемент, если он совпадает с текущим выбранным
                        // ИЛИ если на него навели мышь (xAxisCombo сам меняет highlightedIndex при hover)
                        highlighted: xAxisCombo.currentIndex === index

                        background: Rectangle {
                            // Оставляем дефолтные системные цвета для состояний подсветки
                            color: xAxisCombo.currentIndex === index ? "lightsteelblue" : "transparent"
                        }
                    }
                }

                Label { text: qsTr("Ось Y (Столбцы):") }
                ComboBox {
                    id: yAxisCombo
                    Layout.fillWidth: true
                    // Явно объявляем пустой массив, который заполнится из C++
                    model: []
                    onActivated: update3DGraph()

                    // Решение: явно задаем стандартный делегат с фиксом подсветки
                    delegate: ItemDelegate {
                        width: yAxisCombo.width
                        text: modelData
                        hoverEnabled: true

                        // Принудительно подсвечиваем элемент, если он совпадает с текущим выбранным
                        // ИЛИ если на него навели мышь (yAxisCombo сам меняет highlightedIndex при hover)
                        highlighted: yAxisCombo.currentIndex === index

                        background: Rectangle {
                            // Оставляем дефолтные системные цвета для состояний подсветки
                            color: yAxisCombo.currentIndex === index ? "lightsteelblue" : "transparent"
                        }
                    }
                }

                Label { text: qsTr("Целевой параметр Z:") }
                ComboBox {
                    id: zAxisCombo
                    Layout.fillWidth: true
                    // Явно объявляем пустой массив, который заполнится из C++
                    model: []
                    onActivated: update3DGraph()

                    // Решение: явно задаем стандартный делегат с фиксом подсветки
                    delegate: ItemDelegate {
                        width: zAxisCombo.width
                        text: modelData
                        hoverEnabled: true

                        // Принудительно подсвечиваем элемент, если он совпадает с текущим выбранным
                        // ИЛИ если на него навели мышь (zAxisCombo сам меняет highlightedIndex при hover)
                        highlighted: zAxisCombo.currentIndex === index

                        background: Rectangle {
                            // Оставляем дефолтные системные цвета для состояний подсветки
                            color: zAxisCombo.currentIndex === index ? "lightsteelblue" : "transparent"
                        }
                    }
                }

                Label {
                    text: qsTr("Редактор формул (Пункт 5 ТЗ):")
                    font.bold: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    // Активно, только если выбрана точка на графике
                    enabled: surfaceSeries.selectedPoint.x !== -1 && surfaceSeries.selectedPoint.y !== -1

                    TextField {
                        id: formulaField
                        Layout.fillWidth: true
                        placeholderText: "Пример: V * 1.15 + 0.5"
                        text: "V * 1.10" // Дефолтная формула (увеличить на 10%)
                    }

                    Button {
                        text: qsTr("Применить формулу")
                        Layout.fillWidth: true
                        onClicked: applyCustomFormula()
                    }

                    Label {
                        text: "Переменные: V - значение, X - инд. X, Z - инд. Z"
                        font.pixelSize: 10
                        color: "#7f8c8d"
                    }
                }

                Item { Layout.fillHeight: true } // Распорка
            }
        }

        // ==================== ЦЕНТРАЛЬНАЯ 3D ОБЛАСТЬ ====================
        Rectangle {
            id: centralArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#ffffff"

            // Используем слой, чтобы график растянулся автоматически
            ColumnLayout {
                anchors.fill: parent

                // Информационная панель для вывода данных маркера (Пункт 3 ТЗ)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    color: "#2c3e50"

                    Label {
                        id: markerLabel
                        anchors.centerIn: parent
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: 14
                        text: qsTr("Кликните на карту для замера параметров")
                    }
                }

                Surface3D {
                    id: graph3D
                    // Задаем размеры через свойства Layout вместо width/height
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Было: selectionMode: AbstractGraph3D.SelectionSlice | AbstractGraph3D.SelectionItem
                    // Стало под синтаксис Qt Graphs 6.10:
                    selectionMode: Graphs3D.SelectionFlag.Item

                    theme: GraphsTheme {
                        theme: GraphsTheme.Theme.UserDefined
                        colorStyle: GraphsTheme.ColorStyle.RangeGradient
                        // Для RangeGradient/ObjectGradient настраиваем градиенты:
                        baseGradients: [
                            Gradient {
                                GradientStop { position: 0.0; color: "#0000ff" } // Синий (низ)
                                GradientStop { position: 0.5; color: "#00ff00" } // Зеленый (середина)
                                GradientStop { position: 1.0; color: "#ff0000" } // Красный (верх)
                            }
                        ]
                    }

                    // ---- Добавляем и привязываем оси под ТЗ ----
                    axisX: Value3DAxis {
                        title: xAxisCombo.currentText // Подпись оси X (например, RPM)
                        min: 0.0
                        max: 15.0
                        subSegmentCount: 1
                        titleVisible: true // ОБЯЗАТЕЛЬНО ДЛЯ QT GRAPHS
                    }

                    axisZ: Value3DAxis {
                        title: yAxisCombo.currentText // Подпись оси Z (например, THR)
                        min: 0.0
                        max: 15.0
                        subSegmentCount: 1
                        titleVisible: true // ОБЯЗАТЕЛЬНО ДЛЯ QT GRAPHS
                    }

                    axisY: Value3DAxis {
                        title: zAxisCombo.currentText // Подпись оси Y (Высота — например, UOZ)
                        // Автоматическое масштабирование высоты в зависимости от значений лога
                        segmentCount: 5
                        titleVisible: true // ОБЯЗАТЕЛЬНО ДЛЯ QT GRAPHS
                    }

                    Surface3DSeries {
                        id: surfaceSeries
                        shading: Surface3DSeries.Shading.Smooth
                        drawMode: Surface3DSeries.DrawSurfaceAndWireframe

                        // Отслеживаем клик и перемещение маркера по сетке
                        onSelectedPointChanged: (position) => {
                            if (position.x === -1 || position.y === -1) {
                                markerLabel.text = qsTr("Кликните на карту для замера параметров")
                                return;
                            }

                            // Считываем точное значение из C++ по скорректированным индексам
                            var val = logParser.getMatrixValue(position.y, position.x)

                            markerLabel.text =
                                xAxisCombo.currentText + " (Индекс X: " + position.y + ") | " +
                                yAxisCombo.currentText + " (Индекс Z: " + position.x + ") | " +
                                zAxisCombo.currentText + " = " + val.toFixed(2)
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: qsTr("Выберите файл лога чип-тюнинга")
        nameFilters: ["Логи ЭБУ (*.csv *.txt *.log)"]
        onAccepted: logParser.loadFile(fileDialog.selectedFile)
    }
}
