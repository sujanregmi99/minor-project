#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <math.h>

#include <WiFi.h>
#include <Firebase_ESP_Client.h>

Adafruit_MPU6050 mpu;

// WiFi details
#define WIFI_SSID "homewifi2111_fpkhr_2"
#define WIFI_PASSWORD "SujanRR11@nRR21"

// Firebase details
#define API_KEY "AIzaSyC_VAznxpLqoi9xiCXa1SlTNCIaLT4qrRc"
#define DATABASE_URL "https://vbedas-default-rtdb.asia-southeast1.firebasedatabase.app"

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

float vibrationThreshold = 0.75;
float prevX = 0, prevY = 0, prevZ = 0;

const int ledPin = 2;

unsigned long lastFirebaseUpdate = 0;
unsigned long firebaseInterval = 1000;

unsigned long lastAlertTime = 0;
unsigned long cooldownTime = 60000;

bool firebaseReady = false;

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("System starting...");

  Wire.begin(21, 22);

  pinMode(ledPin, OUTPUT);
  digitalWrite(ledPin, LOW);

  Serial.println("Checking MPU6050...");
  if (!mpu.begin()) {
    Serial.println("MPU6050 not found! Check wiring.");
    while (1) {
      digitalWrite(ledPin, HIGH);
      delay(200);
      digitalWrite(ledPin, LOW);
      delay(200);
    }
  }

  Serial.println("MPU6050 ready!");

  mpu.setAccelerometerRange(MPU6050_RANGE_2_G);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);

  sensors_event_t a, g, temp;
  mpu.getEvent(&a, &g, &temp);

  prevX = a.acceleration.x;
  prevY = a.acceleration.y;
  prevZ = a.acceleration.z;

  Serial.println("Baseline set.");

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("Connecting to WiFi");

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    Serial.print(".");
    delay(500);
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println();
    Serial.println("WiFi connected!");
    Serial.print("IP Address: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println();
    Serial.println("WiFi failed. Continuing without Firebase.");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("Connecting to Firebase...");

    config.api_key = API_KEY;
    config.database_url = DATABASE_URL;

    if (Firebase.signUp(&config, &auth, "", "")) {
      Serial.println("Firebase signup OK");
      firebaseReady = true;
    } else {
      Serial.print("Firebase signup failed: ");
      Serial.println(config.signer.signupError.message.c_str());
      firebaseReady = false;
    }

    Firebase.begin(&config, &auth);
    Firebase.reconnectWiFi(true);

    Serial.println("Firebase setup completed.");
  }

  Serial.println("Entering main loop...");
}

void loop() {
  sensors_event_t a, g, temp;
  mpu.getEvent(&a, &g, &temp);

  float delta = sqrt(
    pow(a.acceleration.x - prevX, 2) +
    pow(a.acceleration.y - prevY, 2) +
    pow(a.acceleration.z - prevZ, 2)
  );

  prevX = a.acceleration.x;
  prevY = a.acceleration.y;
  prevZ = a.acceleration.z;

  String status = "Normal";

  if (delta > vibrationThreshold) {
    status = "Alert";

    Serial.println("Vibration detected!");
    Serial.print("Delta Accel: ");
    Serial.println(delta, 3);

    digitalWrite(ledPin, HIGH);

    if (millis() - lastAlertTime > cooldownTime) {
      sendAlertEvent(delta);
      lastAlertTime = millis();
    }
  } else {
    digitalWrite(ledPin, LOW);
  }

  if (millis() - lastFirebaseUpdate > firebaseInterval) {
  sendLatestData(delta, status);
  lastFirebaseUpdate = millis();
}

  delay(10);
}

void sendLatestData(float delta, String status) {
  if (firebaseReady && Firebase.ready()) {
    bool ok1 = Firebase.RTDB.setFloat(&fbdo, "/latest/acceleration", delta);
    bool ok2 = Firebase.RTDB.setFloat(&fbdo, "/latest/threshold", vibrationThreshold);
    bool ok3 = Firebase.RTDB.setString(&fbdo, "/latest/status", status);
    bool ok4 = Firebase.RTDB.setString(&fbdo, "/latest/timestamp", String(millis() / 1000) + " sec");

    if (ok1 && ok2 && ok3 && ok4) {
      Serial.println("Firebase latest updated.");
    } else {
      Serial.print("Firebase update failed: ");
      Serial.println(fbdo.errorReason());
    }
  } else {
    Serial.println("Firebase not ready.");
  }
}

void sendAlertEvent(float delta) {
  if (firebaseReady && Firebase.ready()) {
    FirebaseJson json;

    json.set("acceleration", delta);
    json.set("threshold", vibrationThreshold);
    json.set("status", "Alert");
    json.set("timestamp", String(millis() / 1000) + " sec");

    if (Firebase.RTDB.pushJSON(&fbdo, "/events", &json)) {
      Serial.println("Alert event pushed to Firebase.");
    } else {
      Serial.print("Event push failed: ");
      Serial.println(fbdo.errorReason());
    }
  }
}