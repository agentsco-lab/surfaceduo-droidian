/**
   @file posturesensor_a.h
   @brief D-Bus adaptor for PostureSensor

   <p>
   Copyright (C) 2016 Canonical LTD.

   @author Lorn Potter <lorn.potter@canonical.com>

   This file is part of Sensorfw.

   Sensord is free software; you can redistribute it and/or modify
   it under the terms of the GNU Lesser General Public License
   version 2.1 as published by the Free Software Foundation.

   Sensord is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with Sensord.  If not, see <http://www.gnu.org/licenses/>.
   </p>
 */

#ifndef POSTURE_SENSOR_H
#define POSTURE_SENSOR_H

#include <QtDBus/QtDBus>
#include <QObject>

#include "datatypes/unsigned.h"
#include "abstractsensor_a.h"

class PostureSensorChannelAdaptor : public AbstractSensorChannelAdaptor
{
    Q_OBJECT
    Q_DISABLE_COPY(PostureSensorChannelAdaptor)
    Q_CLASSINFO("D-Bus Interface", "local.PostureSensor")
    Q_PROPERTY(Unsigned posture READ posture NOTIFY postureChanged)

public:
    PostureSensorChannelAdaptor(QObject* parent);

public Q_SLOTS:
    Unsigned posture() const;

Q_SIGNALS:
    void postureChanged(const Unsigned& value);
};

#endif
