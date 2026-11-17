// Capteur de remplissage : ESP32 + HC-SR04 posé sous le couvercle du conteneur.
#include <WiFi.h>
#include <HTTPClient.h>

const char* WIFI_SSID = "VOTRE_WIFI";
const char* WIFI_PASS = "VOTRE_MOT_DE_PASSE";
const char* API_URL = "http://ADRESSE_API:3000/api/iot/readings";
const char* SENSOR_ID = "conteneur-001";
const char* DEVICE_KEY = "SECRET_REMIS_A_LA_CREATION";
const int TRIG = 5;
const int ECHO = 18;
const uint64_t SLEEP_US = 30ULL * 60ULL * 1000000ULL;

float measureCm() {
  float sum = 0;
  int ok = 0;
  for (int i = 0; i < 7; i++) {
    digitalWrite(TRIG, LOW);
    delayMicroseconds(3);
    digitalWrite(TRIG, HIGH);
    delayMicroseconds(10);
    digitalWrite(TRIG, LOW);
    long t = pulseIn(ECHO, HIGH, 30000);
    if (t > 0) {
      sum += t * 0.0343f / 2.0f;
      ok++;
    }
    delay(60);
  }
  return ok ? sum / ok : -1;
}

void setup() {
  pinMode(TRIG, OUTPUT);
  pinMode(ECHO, INPUT);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) delay(500);
  float d = measureCm();
  if (WiFi.status() == WL_CONNECTED && d > 0) {
    HTTPClient http;
    http.begin(API_URL);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("X-Device-Key", DEVICE_KEY);
    String body = String("{\"sensor_id\":\"") + SENSOR_ID + "\",\"distance_cm\":" + String(d, 1) + "}";
    http.POST(body);
    http.end();
  }
  esp_deep_sleep(SLEEP_US);
}

void loop() {}
