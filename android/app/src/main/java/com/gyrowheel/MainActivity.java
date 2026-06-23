package com.gyrowheel;

import android.app.Activity;
import android.content.Context;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.Bundle;
import android.os.Vibrator;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;

public class MainActivity extends Activity implements SensorEventListener {
    private SensorManager sensorManager;
    private Sensor accelerometer;
    private DatagramSocket socket;
    private String targetIp = "192.168.1.100";
    private int targetPort = 5005;
    private boolean isRunning = false;
    
    private float steer = 0.0f;
    private float throttle = 0.0f;
    private float brake = 0.0f;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        sensorManager = (SensorManager) getSystemService(Context.SENSOR_SERVICE);
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);

        Button startBtn = findViewById(R.id.btn_start);
        EditText ipInput = findViewById(R.id.input_ip);

        startBtn.setOnClickListener(v -> {
            if (!isRunning) {
                targetIp = ipInput.getText().toString();
                isRunning = true;
                startNetworking();
                startBtn.setText("Stop");
            } else {
                isRunning = false;
                startBtn.setText("Start");
            }
        });
    }

    private void startNetworking() {
        new Thread(() -> {
            try {
                socket = new DatagramSocket();
                InetAddress address = InetAddress.getByName(targetIp);
                while (isRunning) {
                    JSONObject json = new JSONObject();
                    json.put("steer", steer);
                    json.put("throttle", throttle);
                    json.put("brake", brake);
                    
                    JSONObject buttons = new JSONObject();
                    for(int i=1; i<=30; i++) {
                        buttons.put("btn" + i, false);
                    }
                    json.put("buttons", buttons);

                    byte[] buf = json.toString().getBytes();
                    DatagramPacket packet = new DatagramPacket(buf, buf.length, address, targetPort);
                    socket.send(packet);
                    Thread.sleep(10);
                }
                socket.close();
            } catch (Exception e) {
                e.printStackTrace();
            }
        }).start();
    }

    @Override
    public void onSensorChanged(SensorEvent event) {
        if (event.sensor.getType() == Sensor.TYPE_ACCELEROMETER) {
            float y = event.values[1];
            steer = Math.max(-1.0f, Math.min(1.0f, y / 9.81f));
        }
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {}

    @Override
    protected void onResume() {
        super.onResume();
        sensorManager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_GAME);
    }

    @Override
    protected void onPause() {
        super.onPause();
        sensorManager.unregisterListener(this);
    }
}
