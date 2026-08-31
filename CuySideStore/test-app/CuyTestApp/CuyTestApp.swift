//
//  CuyTestApp.swift
//  CuySideStore — App de prueba
//
//  App minimalista que ejecuta el escaneo de tampering al iniciar
//  y muestra los resultados en pantalla. Sirve como "conejillo de
//  indias" para validar las detecciones contra los scripts de
//  CuySideStore antes de integrarlas en tu app real.
//
//  ⚠️ SOLO PARA PRUEBAS DE SEGURIDAD EN TUS PROPIAS APPS
//

import SwiftUI
import UIKit

@main
struct CuyTestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var report: TamperReport?
    @State private var logLines: [String] = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Estado general
                    if let report = report {
                        HStack {
                            Image(systemName: report.isCompromised ? "xmark.shield.fill" : "checkmark.shield.fill")
                                .font(.system(size: 40))
                                .foregroundColor(report.isCompromised ? .red : .green)
                            VStack(alignment: .leading) {
                                Text(report.isCompromised ? "COMPROMETIDO" : "LIMPIO")
                                    .font(.title.bold())
                                Text("Risk score: \(report.riskScore)/100")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(report.isCompromised ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }

                    // Botón de escaneo
                    Button(action: runScan) {
                        Label("Ejecutar escaneo", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    // Resultados detallados
                    if let report = report {
                        Group {
                            DetectionRow(title: "1. Team ID incorrecto", isDetected: report.wrongTeamId)
                            DetectionRow(title: "2. Bundle ID modificado", isDetected: report.modifiedBundleId)
                            DetectionRow(title: "3. Sin App Store receipt", isDetected: report.noAppStoreReceipt)
                            DetectionRow(title: "4. Entitlements de desarrollo", isDetected: report.hasDevEntitlements)
                            DetectionRow(title: "5. Perfil embebido presente", isDetected: report.hasEmbeddedProfile)
                            DetectionRow(title: "6. Imágenes sospechosas cargadas", isDetected: report.suspiciousImages)
                            DetectionRow(title: "7. Variables de inyección", isDetected: report.injectionEnvVars)
                            DetectionRow(title: "8. Debugger adjunto", isDetected: report.debuggerAttached)
                        }
                    }

                    // Log de consola
                    if !logLines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Log de detección")
                                .font(.headline)
                            ForEach(logLines, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("CuyTestApp")
            .onAppear { runScan() }
        }
    }

    private func runScan() {
        logLines.removeAll()

        // Capturar los prints en un log visible
        let newReport = TamperDetector.performFullScan()
        report = newReport

        // Capturar output de consola para mostrarlo en pantalla
        // (los prints van a la consola de Xcode, aquí mostramos el resumen)
        logLines = [
            "Team ID: \(newReport.wrongTeamId ? "❌ incorrecto" : "✓ correcto")",
            "Bundle ID: \(newReport.modifiedBundleId ? "❌ modificado" : "✓ correcto")",
            "Receipt: \(newReport.noAppStoreReceipt ? "❌ ausente" : "✓ presente")",
            "Entitlements: \(newReport.hasDevEntitlements ? "❌ desarrollo" : "✓ producción")",
            "Perfil embebido: \(newReport.hasEmbeddedProfile ? "❌ presente" : "✓ ausente")",
            "Imágenes: \(newReport.suspiciousImages ? "❌ sospechosas" : "✓ limpias")",
            "Env vars: \(newReport.injectionEnvVars ? "❌ inyección" : "✓ limpias")",
            "Debugger: \(newReport.debuggerAttached ? "❌ adjunto" : "✓ no adjunto")",
            "───",
            "Risk score: \(newReport.riskScore)/100",
            newReport.isCompromised ? "RESULTADO: ❌ COMPROMETIDO" : "RESULTADO: ✓ LIMPIO"
        ]
    }
}

struct DetectionRow: View {
    let title: String
    let isDetected: Bool

    var body: some View {
        HStack {
            Image(systemName: isDetected ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isDetected ? .red : .green)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(isDetected ? "DETECTADO" : "OK")
                .font(.caption.bold())
                .foregroundColor(isDetected ? .red : .green)
        }
        .padding(.vertical, 4)
        .padding(.horizontal)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}