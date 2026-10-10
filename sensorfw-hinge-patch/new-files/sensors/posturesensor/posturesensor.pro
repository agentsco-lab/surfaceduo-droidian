CONFIG      += link_pkgconfig

TARGET       = posturesensor

HEADERS += posturesensor.h   \
           posturesensor_a.h \
           postureplugin.h

SOURCES += posturesensor.cpp   \
           posturesensor_a.cpp \
           postureplugin.cpp

include( ../sensor-config.pri )

contextprovider {
    DEFINES += PROVIDE_CONTEXT_INFO
    PKGCONFIG += contextprovider-1.0
}

