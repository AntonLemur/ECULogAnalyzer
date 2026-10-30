#ifndef LOGPARSER_H
#define LOGPARSER_H

#include <QObject>
#include <QString>
#include <QVector>
#include <QMap>
#include <QStringList>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>
#include <QtGraphs/qsurface3dseries.h>
#include <QtGraphs/qsurfacedataproxy.h>
#include <QtGui/qvector3d.h>

// Структура для хранения одного из 10 возможных логов
struct LogFileData {
    QString fileName;
    QStringList headers;
    // Ключ — имя параметра (например, "RPM"), значение — массив точек по времени
    QMap<QString, QVector<double>> dataMap;
    int rowCount = 0;
};

class LogParser : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList loadedLogs READ loadedLogs NOTIFY loadedLogsChanged)
    Q_PROPERTY(int activeLogIndex READ getActiveLogIndex WRITE setActiveLogIndex NOTIFY activeLogIndexChanged)
    QML_ELEMENT

public:
    explicit LogParser(QObject *parent = nullptr);

    // Слот для QML: загрузка файла (до 10 штук без удаления старых)
    Q_INVOKABLE bool loadFile(const QString &filePath);

    // Очистить все логи
    Q_INVOKABLE void clearAll();

    // Получить список заголовков конкретного лога по индексу (0-9)
    Q_INVOKABLE QStringList getHeaders(int logIndex = 0) const;

    // Генерация 3D сетки 16x16 на основе выбранных осей X, Y и целевого параметра Z
    // Возвращает плоский массив из 256 значений для Qt Graphs Surface3D
    Q_INVOKABLE void generate3DMatrix(QSurface3DSeries *series,
                                              int logIndex,
                                              const QString &xHeader,
                                              const QString &yHeader,
                                              const QString &zHeader,
                                              int minHits = 1);

    Q_INVOKABLE double getMatrixValue(int row, int col) const;
    Q_INVOKABLE double getCurrentMinY() const;
    Q_INVOKABLE double getCurrentMaxY() const;
    Q_INVOKABLE void updateActiveSeries(QSurface3DSeries *series);
    Q_INVOKABLE void applyFormula(int row, int col, const QString &formulaStr);
    Q_INVOKABLE int getActiveLogIndex() const { return m_activeLogIndex; }
    Q_INVOKABLE void setActiveLogIndex(int index) {
        if (index >= 0 && index < m_logs.size()) {
            m_activeLogIndex = index;
            emit activeLogIndexChanged(); // <- Оповещаем QML
        }
    }
    Q_INVOKABLE int getHitCount(int row, int col) const;

    QStringList loadedLogs() const { return m_loadedLogNames; }

signals:
    void loadedLogsChanged();
    void errorOccurred(const QString &message);
    void searchProgress(int current, int total); // Отображение хода поиска (Пункт 4 ТЗ)
    void activeLogIndexChanged();

private:
    char detectSeparator(const QString &headerLine);

    QVector<LogFileData> m_logs;       // Хранилище до 10 логов
    QStringList m_loadedLogNames;      // Список имен для QML SideBar/Combo
    double m_currentGrid[16][16] = {0.0};
    int m_currentHitGrid[16][16] = {0};
    int m_activeLogIndex = 0;
};

#endif // LOGPARSER_H
