TARGET       = hybrispostureadaptor

HEADERS += hybrispostureadaptor.h \
           hybrispostureadaptorplugin.h

SOURCES += hybrispostureadaptor.cpp \
           hybrispostureadaptorplugin.cpp
LIBS+= -L../../core -lhybrissensorfw-qt$${QT_MAJOR_VERSION}

include( ../adaptor-config.pri )
config_hybris {
    PKGCONFIG += android-headers
}
