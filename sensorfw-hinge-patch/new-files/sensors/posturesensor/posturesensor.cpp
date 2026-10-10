/**
   @file posturesensor.cpp
   @brief PostureSensor

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

#include "posturesensor.h"

#include "sensormanager.h"
#include "bin.h"
#include "bufferreader.h"

PostureSensorChannel::PostureSensorChannel(const QString& id) :
        AbstractSensorChannel(id),
        DataEmitter<TimedUnsigned>(1),
        previousValue_(0,0)
{
    SensorManager& sm = SensorManager::instance();

    postureAdaptor_ = sm.requestDeviceAdaptor("postureadaptor");
    if (!postureAdaptor_) {
        setValid(false);
        return;
    }

    postureReader_ = new BufferReader<TimedUnsigned>(1);

    outputBuffer_ = new RingBuffer<TimedUnsigned>(1);

    // Create buffers for filter chain
    filterBin_ = new Bin;

    filterBin_->add(postureReader_, "posture");
    filterBin_->add(outputBuffer_, "buffer");

    filterBin_->join("posture", "source", "buffer", "sink");

    // Join datasources to the chain
    connectToSource(postureAdaptor_, "posture", postureReader_);

    marshallingBin_ = new Bin;
    marshallingBin_->add(this, "sensorchannel");

    outputBuffer_->join(this);

    setDescription("ambient posture in pascals");
    setRangeSource(postureAdaptor_);
    addStandbyOverrideSource(postureAdaptor_);
    setIntervalSource(postureAdaptor_);

    setValid(true);
}

PostureSensorChannel::~PostureSensorChannel()
{
    if (isValid()) {
        SensorManager& sm = SensorManager::instance();

        disconnectFromSource(postureAdaptor_, "posture", postureReader_);

        sm.releaseDeviceAdaptor("postureadaptor");

        delete postureReader_;
        delete outputBuffer_;
        delete marshallingBin_;
        delete filterBin_;
    }
}

bool PostureSensorChannel::start()
{
    sensordLogD() << id() << "Starting PostureSensorChannel";

    if (AbstractSensorChannel::start()) {
        marshallingBin_->start();
        filterBin_->start();
        postureAdaptor_->startSensor();
    }
    return true;
}

bool PostureSensorChannel::stop()
{
    sensordLogD() << id() << "Stopping PostureSensorChannel";

    if (AbstractSensorChannel::stop()) {
        postureAdaptor_->stopSensor();
        filterBin_->stop();
        marshallingBin_->stop();
    }
    return true;
}

void PostureSensorChannel::emitData(const TimedUnsigned& value)
{
    if (value.value_ != previousValue_.value_) {
        previousValue_.value_ = value.value_;

        writeToClients((const void*)(&value), sizeof(value));
    }
}
