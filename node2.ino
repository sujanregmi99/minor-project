#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <math.h>

#include <WiFi.h>
#include <Firebase_ESP_Client.h>

Adafruit_MPU6050 mpu;

// WiFi details
#define WIFI_SSID "homewifi_fpkhr_2"
#define WIFI_PASSWORD "SujanRR11@nRR21"

// Firebase details
#define API_KEY "AIzaSyC_VAznxpLqoi9xiCXa1SlTNCIaLT4qrRc"
#define DATABASE_URL "https://vbedas-default-rtdb.asia-southeast1.firebasedatabase.app/"

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// Same threshold logic as first node
float vibrationThreshold = 0.75;
float prevX = 0, prevY = 0, prevZ = 0;

// Optional onboard LED for checking only
const int ledPin = 2;

unsigned long lastFirebaseUpdate = 0;
unsigned long firebaseInterval = 500; // update every 0.5 sec

unsigned long lastDetectionTime = 0;
unsigned long activeAlertWindow = 3000; // keep status Alert for 3 seconds

bool firebaseReady = false;

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("Checker Node Starting...");

  Wire.begin(21, 22); // SDA=21, SCL=22

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

  Serial.println("Baseline set. Checker node monitoring vibrations...");

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
    Serial.println("WiFi failed. Firebase will not update.");
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

  Serial.println("Checker node entering main loop...");
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

  if (delta > vibrationThreshold) {
    lastDetectionTime = millis();
    digitalWrite(ledPin, HIGH);

    Serial.println("Checker Node: Vibration detected!");
    Serial.print("Delta Accel: ");
    Serial.println(delta, 3);
  }

  String status = "Normal";

  if (millis() - lastDetectionTime <= activeAlertWindow) {
    status = "Alert";
    digitalWrite(ledPin, HIGH);
  } else {
    status = "Normal";
    digitalWrite(ledPin, LOW);
  }

  if (millis() - lastFirebaseUpdate > firebaseInterval) {
    sendCheckerData(delta, status);
    lastFirebaseUpdate = millis();
  }

  delay(10);
}

void sendCheckerData(float delta, String status) {
  if (firebaseReady && Firebase.ready()) {
    Firebase.RTDB.setFloat(&fbdo, "/node2/delta", delta);
    Firebase.RTDB.setFloat(&fbdo, "/node2/threshold", vibrationThreshold);
    Firebase.RTDB.setString(&fbdo, "/node2/status", status);
    Firebase.RTDB.setInt(&fbdo, "/node2/lastDetectionMillis", lastDetectionTime);
    Firebase.RTDB.setString(&fbdo, "/node2/device", "Secondary Verification Node");
    Firebase.RTDB.setString(&fbdo, "/node2/online", "true");
  }
}