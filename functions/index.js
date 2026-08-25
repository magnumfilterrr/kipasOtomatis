const { onValueWritten } = require("firebase-functions/v2/database");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const fonnteToken = defineSecret("FONNTE_TOKEN");

// notif WA
async function kirimWhatsApp(token, nomorTujuan, pesan) {
  try {
    const response = await fetch("https://api.fonnte.com/send", {
      method: "POST",
      headers: {
        Authorization: token,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        target: nomorTujuan,
        message: pesan,
        countryCode: "62",
      }),
    });
    const hasil = await response.json();
    console.log("Respon Fonnte:", JSON.stringify(hasil));
  } catch (err) {
    console.log("Gagal kirim WhatsApp:", err.message);
  }
}

exports.cekSuhuDanNotifikasi = onValueWritten(
  {
    ref: "/sensor/suhu",
    region: "asia-southeast1",
    instance: "kipas-otomatis-7d7da-default-rtdb",
    secrets: [fonnteToken],
  },
  async (event) => {
    const suhu = event.data.after.val();

    if (suhu == null) return;

    const db = getDatabase();

    const settingsSnap = await db.ref("/settings").once("value");
    const settings = settingsSnap.val() || {};

    const thresholdMin = settings.threshold_min ?? 25;
    const thresholdMax = settings.threshold_max ?? 30;
    const thresholdEmergency = settings.threshold_emergency ?? 45;
    const nomorWa = settings.nomor_wa; // contoh: "6281234567890"

    const tokenSnap = await db.ref("/device_token").once("value");
    const token = tokenSnap.val();

    // Notif Darurat
    if (suhu >= thresholdEmergency) {
      const lastEmergencySnap = await db.ref("/sensor/last_emergency_notif").once("value");
      const lastEmergencyTime = lastEmergencySnap.val() || 0;
      const sekarang = Date.now();
      const LIMA_MENIT = 5 * 60 * 1000;

      if (sekarang - lastEmergencyTime > LIMA_MENIT) {
        await db.ref("/sensor/last_emergency_notif").set(sekarang);

        const judulDarurat = "⚠️ SUHU DARURAT!";
        const isiDarurat = `Suhu mencapai ${suhu.toFixed(1)}°C, sudah melewati batas darurat (${thresholdEmergency}°C). Segera periksa!`;

        if (token) {
          await getMessaging().send({
            token,
            data: { title: judulDarurat, body: isiDarurat },
            android: { priority: "high" },
          });
        }

        if (nomorWa) {
          await kirimWhatsApp(fonnteToken.value(), nomorWa, `*${judulDarurat}*\n${isiDarurat}`);
        }

        console.log("Notifikasi DARURAT berhasil dikirim.");
      }
      return;
    }
    //logika notifikasi normal
    let statusBaru = null;
    let judul = null;
    let isi = null;

    if (suhu >= thresholdMax) {
      statusBaru = "tinggi";
      judul = "Suhu Tinggi!";
      isi = `Suhu saat ini ${suhu.toFixed(1)}°C, kipas menyala.`;
    } else if (suhu <= thresholdMin) {
      statusBaru = "normal";
      judul = "Suhu Normal";
      isi = `Suhu saat ini ${suhu.toFixed(1)}°C, kipas mati.`;
    } else {
      return;
    }

    const lastStatusSnap = await db.ref("/sensor/last_notif_status").once("value");
    const statusLama = lastStatusSnap.val();

    if (statusBaru === statusLama) {
      return;
    }

    await db.ref("/sensor/last_notif_status").set(statusBaru);

    if (token) {
      await getMessaging().send({
        token,
        data: { title: judul, body: isi },
        android: { priority: "high" },
      });
    }

    if (nomorWa) {
      await kirimWhatsApp(fonnteToken.value(), nomorWa, `*${judul}*\n${isi}`);
    }

    console.log("Notifikasi berhasil dikirim.");
  }
);