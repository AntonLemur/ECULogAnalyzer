#include "logparser.h"
#include <QFile>
#include <QTextStream>
#include <QUrl>
#include <QDebug>
#include <cmath>
#include <QJSEngine>

LogParser::LogParser(QObject *parent) : QObject(parent) {}

char LogParser::detectSeparator(const QString &headerLine)
{
    int commas = headerLine.count(',');
    int semicolons = headerLine.count(';');
    return (semicolons > commas) ? ';' : ',';
}

void LogParser::clearAll()
{
    m_logs.clear();
    m_loadedLogNames.clear();
    emit loadedLogsChanged();
}

bool LogParser::loadFile(const QString &filePath)
{
    if (m_logs.size() >= 10) {
        emit errorOccurred(tr("Максимальное количество логов для сравнения (10) уже достигнуто."));
        return false;
    }

    QString cleanPath = filePath;
    if (cleanPath.startsWith("file:///")) {
        cleanPath = QUrl(filePath).toLocalFile();
    }

    QFile file(cleanPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit errorOccurred(tr("Ошибка открытия файла: %1").arg(file.errorString()));
        return false;
    }

    QTextStream in(&file);
    if (in.atEnd()) return false;

    QString headerLine = in.readLine();
    char sep = detectSeparator(headerLine);

    LogFileData newLog;
    newLog.fileName = file.fileName().section('/', -1);

    // Формируем чистый список заголовков
    for (const auto &h : headerLine.split(sep)) {
        newLog.headers.append(h.trimmed().toUpper());
    }

    // Инициализируем векторы под каждый заголовок
    for (const auto &header : newLog.headers) {
        newLog.dataMap[header] = QVector<double>();
    }

    // Чтение данных
    int rowCounter = 0;
    while (!in.atEnd()) {
        QString line = in.readLine();
        if (line.isEmpty()) continue;

        QStringList tokens = line.split(sep);
        if (tokens.size() < newLog.headers.size()) continue;

        for (int i = 0; i < newLog.headers.size(); ++i) {
            newLog.dataMap[newLog.headers[i]].append(tokens[i].toDouble());
        }
        rowCounter++;
    }

    newLog.rowCount = rowCounter;
    m_logs.append(newLog);
    m_loadedLogNames.append(newLog.fileName);

    emit loadedLogsChanged();
    return true;
}

QStringList LogParser::getHeaders(int logIndex) const
{
    if (logIndex < 0 || logIndex >= m_logs.size()) return QStringList();
    return m_logs[logIndex].headers;
}

// Построение калибровочной сетки 16x16 (Пункт 2 и 9 ТЗ)
void LogParser::generate3DMatrix(QSurface3DSeries *series,
                                         int logIndex,
                                         const QString &xHeader,
                                         const QString &yHeader,
                                         const QString &zHeader,
                                         int minHits)
{
    if (!series || !series->dataProxy()) return;

    // 1. Создаем структуру данных QtGraphs для 3D поверхности
    QSurfaceDataArray dataArray;
    dataArray.reserve(16);

    if (logIndex < 0 || logIndex >= m_logs.size()) return;

    const auto &log = m_logs[logIndex];
    if (!log.dataMap.contains(xHeader) || !log.dataMap.contains(yHeader) || !log.dataMap.contains(zHeader)) {
        return;
    }

    const auto &xData = log.dataMap[xHeader];
    const auto &yData = log.dataMap[yHeader];
    const auto &zData = log.dataMap[zHeader];

    // Находим минимумы и максимумы для квантования осей
    auto xMinMax = std::minmax_element(xData.begin(), xData.end());
    auto yMinMax = std::minmax_element(yData.begin(), yData.end());

    double xMin = *xMinMax.first;  double xMax = *xMinMax.second;
    double yMin = *yMinMax.first;  double yMax = *yMinMax.second;

    // Сетки 16x16 для суммирования значений и подсчета хитов (попаданий)
    double sumGrid[16][16] = {0.0};
    int hitGrid[16][16] = {0};

    int totalPoints = log.rowCount;

    // Распределяем точки лога по ячейкам 16x16
    for (int i = 0; i < totalPoints; ++i) {
        if (i % 5 == 0) emit searchProgress(i, totalPoints); // Имитация/вывод хода поиска для UI

        double xVal = xData[i];
        double yVal = yData[i];
        double zVal = zData[i];

        // Вычисляем индекс в матрице 16x16
        int xIdx = (xMax - xMin > 0) ? qBound(0, static_cast<int>((xVal - xMin) / (xMax - xMin) * 15), 15) : 0;
        int yIdx = (yMax - yMin > 0) ? qBound(0, static_cast<int>((yVal - yMin) / (yMax - yMin) * 15), 15) : 0;

        sumGrid[xIdx][yIdx] += zVal;
        hitGrid[xIdx][yIdx]++;
    }
    emit searchProgress(totalPoints, totalPoints);

    // 1. Сначала рассчитываем средние значения для ячеек, где ЕСТЬ попадания,
    // а для пустых ячеек ставим -1.0 (флаг отсутствия данных)
    double finalGrid[16][16];
    for (int x = 0; x < 16; ++x) {
        for (int z = 0; z < 16; ++z) {
            if (hitGrid[x][z] >= minHits) {
                finalGrid[x][z] = sumGrid[x][z] / hitGrid[x][z];
            } else {
                finalGrid[x][z] = -1.0; // Помечаем как пустую ячейку
            }
        }
    }

    // 2. Алгоритм интерполяции (Заполнение пустых зон)
    // Проходим по всей сетке. Если ячейка пустая, ищем ближайшую заполненную ячейку по оси X
    for (int x = 0; x < 16; ++x) {
        for (int z = 0; z < 16; ++z) {
            if (finalGrid[x][z] == -1.0) {
                // Ищем ближайшего соседа с реальными данными в той же строчке/столбце
                double nearestValidVal = 0.0;
                bool found = false;

                // Сначала ищем по оси оборотов (X) в текущем ряду нагрузки
                for (int lookX = 0; lookX < 16; ++lookX) {
                    if (finalGrid[lookX][z] != -1.0) {
                        nearestValidVal = finalGrid[lookX][z];
                        found = true;
                        break;
                    }
                }

                // Если вся строка пустая, ищем по оси нагрузки (Z)
                if (!found) {
                    for (int lookZ = 0; lookZ < 16; ++lookZ) {
                        if (finalGrid[x][lookZ] != -1.0) {
                            nearestValidVal = finalGrid[x][lookZ];
                            found = true;
                            break;
                        }
                    }
                }

                // Заполняем ячейку базовым или интерполированным значением
                finalGrid[x][z] = found ? nearestValidVal : 0.0;
            }
        }
    }

    // 3. Передаем готовую и сглаженную матрицу в Qt Graphs
    for (int x = 0; x < 16; ++x) {
        QSurfaceDataRow row;
        row.reserve(16);
        float xCoord = static_cast<float>(x);

        for (int z = 0; z < 16; ++z) {
            float zCoord = static_cast<float>(z);

            // СОХРАНЯЕМ ТЕКУЩЕЕ ЗНАЧЕНИЕ ДЛЯ МАРКЕРА
            m_currentGrid[x][z] = finalGrid[x][z];

            row.append(QSurfaceDataItem(QVector3D(xCoord,
                                                  static_cast<float>(finalGrid[x][z]),
                                                  zCoord)));
        }
        dataArray.append(row);
    }

    series->dataProxy()->resetArray(dataArray);
}

// Реализация нового метода считывания значения ячейки
double LogParser::getMatrixValue(int row, int col) const
{
    if (row < 0 || row >= 16 || col < 0 || col >= 16) return 0.0;
    return m_currentGrid[row][col];
}

double LogParser::getCurrentMinY() const
{
    double minVal = m_currentGrid[0][0];
    for (int x = 0; x < 16; ++x) {
        for (int z = 0; z < 16; ++z) {
            if (m_currentGrid[x][z] < minVal) minVal = m_currentGrid[x][z];
        }
    }
    return minVal;
}

double LogParser::getCurrentMaxY() const
{
    double maxVal = m_currentGrid[0][0];
    for (int x = 0; x < 16; ++x) {
        for (int z = 0; z < 16; ++z) {
            if (m_currentGrid[x][z] > maxVal) maxVal = m_currentGrid[x][z];
        }
    }
    return maxVal;
}

void LogParser::updateActiveSeries(QSurface3DSeries *series)
{
    if (!series || !series->dataProxy()) return;

    QSurfaceDataArray dataArray;
    dataArray.reserve(16);

    for (int x = 0; x < 16; ++x) {
        QSurfaceDataRow row;
        row.reserve(16);
        float xCoord = static_cast<float>(x);

        for (int z = 0; z < 16; ++z) {
            float zCoord = static_cast<float>(z);
            row.append(QSurfaceDataItem(QVector3D(xCoord, static_cast<float>(m_currentGrid[x][z]), zCoord)));
        }
        dataArray.append(row);
    }
    series->dataProxy()->resetArray(dataArray);
}

void LogParser::applyFormula(int row, int col, const QString &formulaStr)
{
    if (row < 0 || row >= 16 || col < 0 || col >= 16) return;

    double currentV = m_currentGrid[row][col];

    // Инициализируем изолированный движок JavaScript
    QJSEngine jsEngine;

    // Регистрируем переменные для формулы (Пункт 5 ТЗ)
    jsEngine.globalObject().setProperty("V", currentV);
    jsEngine.globalObject().setProperty("X", row);
    jsEngine.globalObject().setProperty("Z", col);

    // Вычисляем выражение, введенное пользователем
    QJSValue resultValue = jsEngine.evaluate(formulaStr);

    if (resultValue.isError()) {
        emit errorOccurred(tr("Ошибка в формуле: %1").arg(resultValue.toString()));
        return;
    }

    double result = resultValue.toNumber();

    if (std::isnan(result) || std::isinf(result)) {
        emit errorOccurred(tr("Результат вычисления не является числом."));
        return;
    }

    if (result < 0.0) result = 0.0; // Защита от некорректных значений

    // Сохраняем результат в нашу матрицу
    m_currentGrid[row][col] = result;
}

