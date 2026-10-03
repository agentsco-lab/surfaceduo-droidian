/****************************************************************************
**
** Copyright (C) 2013 Jolla Ltd
**
** Copyright (C) 2017 Matti Lehtimäki
**
** $QT_BEGIN_LICENSE:LGPL$
**
** GNU Lesser General Public License Usage
** Alternatively, this file may be used under the terms of the GNU Lesser
** General Public License version 2.1 as published by the Free Software
** Foundation and appearing in the file LICENSE.LGPL included in the
** packaging of this file.  Please review the following information to
** ensure the GNU Lesser General Public License version 2.1 requirements
** will be met: http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
**
** $QT_END_LICENSE$
**
****************************************************************************/

#include <QFile>
#include <QTextStream>

#include "hybrispostureadaptor.h"
#include "logging.h"
#include "datatypes/utils.h"
#include "config.h"

HybrisPostureAdaptor::HybrisPostureAdaptor(const QString& id) :
    HybrisAdaptor(id,SENSOR_TYPE_SURFACE_POSTURE)
{
    buffer = new DeviceAdaptorRingBuffer<TimedUnsigned>(1);
    setAdaptedSensor("posture", "Microsoft posture (Surface Duo)", buffer);
    setDescription("Hybris Surface posture");
    powerStatePath = SensorFrameworkConfig::configuration()->value("posture/powerstate_path").toByteArray();
    if (!powerStatePath.isEmpty() && !QFile::exists(powerStatePath))
    {
        sensordLogW() << NodeBase::id() << "Path does not exists: " << powerStatePath;
        powerStatePath.clear();
    }
}

HybrisPostureAdaptor::~HybrisPostureAdaptor()
{
    delete buffer;
}

bool HybrisPostureAdaptor::startSensor()
{
    if (!(HybrisAdaptor::startSensor()))
        return false;
    if (isRunning() && !powerStatePath.isEmpty())
        writeToFile(powerStatePath, "1");
    sensordLogD() << id() << "Hybris HybrisPostureAdaptor start";
    return true;
}

void HybrisPostureAdaptor::stopSensor()
{
    HybrisAdaptor::stopSensor();
    if (!isRunning() && !powerStatePath.isEmpty())
        writeToFile(powerStatePath, "0");
    sensordLogD() << id() << "Hybris HybrisPostureAdaptor stop";
}

void HybrisPostureAdaptor::processSample(const sensors_event_t& data)
{
    // Microsoft's posture sensor (the vendor type 33171009): what its values
    // mean is not published - the first is taken as the posture's number,
    // and the first four logged at each change, to be read against the
    // ways the Duo is held.
#ifdef USE_BINDER
    const float *v = data.u.data;
#else
    const float *v = data.data;
#endif
    if (v[0] != m_last[0] || v[1] != m_last[1] || v[2] != m_last[2] || v[3] != m_last[3]) {
        sensordLogW() << "Surface posture:" << v[0] << v[1] << v[2] << v[3];
        for (int i = 0; i < 4; i++)
            m_last[i] = v[i];
    }
    TimedUnsigned *d = buffer->nextSlot();
    d->timestamp_ = quint64(data.timestamp * .001);
    d->value_ = (unsigned)v[0];
    buffer->commit();
    buffer->wakeUpReaders();
}
