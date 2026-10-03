// Writes a pre-generated pairing into Moonlight's own settings, so it streams
// from the gaming desktop without ever pairing by PIN.
//
// Qt itself does the writing: Moonlight.conf is a QSettings INI file whose
// certs and MAC are @ByteArray values in Qt's own escaping, and going through
// QSettings is the only way to be sure Moonlight reads back exactly what was
// meant. Keys are moonlight-qt 6.1's (backend/identitymanager.cpp,
// backend/nvcomputer.cpp, backend/computermanager.cpp).
//
// Only the pairing is touched: the client identity, and the one host entry
// whose uuid matches. Moonlight's preferences, other hosts and whatever it
// learned about this host (its app list, IPv6 address) stay.

#include <QCommandLineParser>
#include <QCoreApplication>
#include <QFile>
#include <QSettings>

#include <cstdio>
#include <cstdlib>

namespace {

[[noreturn]] void fail(const QString &message)
{
    std::fprintf(stderr, "moonlight-seed: %s\n", qPrintable(message));
    std::exit(1);
}

QByteArray readFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        fail(QString("reading %1: %2").arg(path, file.errorString()));
    }
    return file.readAll();
}

// "2c:f0:5d:cf:62:1a" -> the 6 raw bytes Moonlight keeps (it parses the
// server's MAC the same way, NvHTTP::getServerInfo -> fromHex).
QByteArray parseMac(QString mac)
{
    QByteArray bytes = QByteArray::fromHex(mac.remove(':').toLatin1());
    if (bytes.size() != 6) {
        fail(QString("not a MAC address: %1").arg(mac));
    }
    return bytes;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    // Where Moonlight's QSettings live: ~/.config/<organization>/<application>.conf
    QCoreApplication::setOrganizationName("Moonlight Game Streaming Project");
    QCoreApplication::setOrganizationDomain("moonlight-stream.com");
    QCoreApplication::setApplicationName("Moonlight");

    QCommandLineParser parser;
    parser.setApplicationDescription("Seed Moonlight.conf with a pre-generated pairing.");
    parser.addHelpOption();
    const QList<QCommandLineOption> options = {
        {"cert", "This client's certificate (PEM).", "file"},
        {"key", "This client's private key (PEM).", "file"},
        {"uniqueid", "This client's unique id.", "hex"},
        {"host-uuid", "The host's uniqueid, as Sunshine reports it.", "uuid"},
        {"host-name", "The host's name, as Sunshine reports it.", "name"},
        {"host-address", "Where to reach the host.", "address"},
        {"host-mac", "The host's MAC, for Wake-on-LAN.", "aa:bb:cc:dd:ee:ff"},
        {"host-cert", "The host's certificate (PEM).", "file"},
    };
    parser.addOptions(options);
    parser.process(app);
    for (const QCommandLineOption &option : options) {
        if (parser.value(option).isEmpty()) {
            fail(QString("--%1 is required").arg(option.names().first()));
        }
    }

    const QString hostUuid = parser.value("host-uuid");
    QSettings settings;

    settings.setValue("certificate", readFile(parser.value("cert")));
    settings.setValue("key", readFile(parser.value("key")));
    settings.setValue("uniqueid", parser.value("uniqueid"));

    // A non-empty hostsbackup means Moonlight died mid-flush, and it reads
    // that instead of hosts on its next start (ComputerManager's constructor).
    // Edit whichever one it will read.
    const QString array = settings.beginReadArray("hostsbackup") > 0 ? "hostsbackup" : "hosts";
    settings.endArray();

    const int count = settings.beginReadArray(array);
    int index = count;
    for (int i = 0; i < count; i++) {
        settings.setArrayIndex(i);
        if (settings.value("uuid").toString().compare(hostUuid, Qt::CaseInsensitive) == 0) {
            index = i;
            break;
        }
    }
    settings.endArray();

    const QString address = parser.value("host-address");
    const uint httpPort = 47989; // GameStream's, and Sunshine's default
    settings.beginWriteArray(array, qMax(count, index + 1));
    settings.setArrayIndex(index);
    settings.setValue("hostname", parser.value("host-name"));
    settings.setValue("customname", false);
    settings.setValue("uuid", hostUuid);
    settings.setValue("mac", parseMac(parser.value("host-mac")));
    settings.setValue("localaddress", address);
    settings.setValue("localport", httpPort);
    settings.setValue("manualaddress", address);
    settings.setValue("manualport", httpPort);
    settings.setValue("srvcert", readFile(parser.value("host-cert")));
    settings.setValue("nvidiasw", false);
    settings.endArray();

    settings.sync();
    if (settings.status() != QSettings::NoError) {
        fail(QString("writing %1 failed").arg(settings.fileName()));
    }
    std::printf("moonlight-seed: paired %s (%s) in %s\n",
                qPrintable(parser.value("host-name")), qPrintable(hostUuid),
                qPrintable(settings.fileName()));
    return 0;
}
