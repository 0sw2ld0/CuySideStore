//
//  TamperDetector.swift
//  CuySideStore — App de prueba
//
//  Implementa las detecciones que quieres validar contra los
//  scripts de CuySideStore. Cada detección imprime su resultado
//  en consola para que puedas verificar qué funciona y qué no.
//
//  ⚠️ SOLO PARA PRUEBAS DE SEGURIDAD EN TUS PROPIAS APPS
//

import Foundation
import MachO
import Security
import UIKit

struct TamperReport {
    let wrongTeamId: Bool
    let modifiedBundleId: Bool
    let noAppStoreReceipt: Bool
    let hasDevEntitlements: Bool
    let hasEmbeddedProfile: Bool
    let suspiciousImages: Bool
    let injectionEnvVars: Bool
    let debuggerAttached: Bool

    var riskScore: Int {
        var score = 0
        if wrongTeamId { score += 30 }
        if modifiedBundleId { score += 10 }
        if noAppStoreReceipt { score += 10 }
        if hasDevEntitlements { score += 15 }
        if hasEmbeddedProfile { score += 25 }
        if suspiciousImages { score += 25 }
        if injectionEnvVars { score += 15 }
        if debuggerAttached { score += 10 }
        return min(score, 100)
    }

    var isCompromised: Bool {
        return riskScore >= 30
    }
}

enum TamperDetector {

    // MARK: - Detección 1: Team ID incorrecto
    // Validar con: resign_ipa.sh (re-firma con otro certificado)

    static func hasWrongTeamId() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let teamId = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.developer.team-identifier" as CFString,
                  nil
              ) as? String else {
            print("[DETECCIÓN 1] ⚠️ Sin Team ID — firma alterada o inválida")
            return true
        }

        // ⚠️ REEMPLAZA con TU Team ID real de Apple Developer
        let expectedTeamId = "TU_TEAM_ID_AQUI"

        let isWrong = teamId != expectedTeamId
        print("[DETECCIÓN 1] Team ID: \(teamId) — \(isWrong ? "❌ NO coincide" : "✓ correcto")")
        return isWrong
    }

    // MARK: - Detección 2: Bundle ID modificado
    // Validar con: resign_ipa.sh con bundle ID diferente

    static func hasModifiedBundleId() -> Bool {
        let current = Bundle.main.bundleIdentifier ?? ""
        // ⚠️ REEMPLAZA con TU bundle ID real
        let expected = "com.cuycoders.testapp"

        let isModified = current != expected
        print("[DETECCIÓN 2] Bundle ID: \(current) — \(isModified ? "❌ modificado" : "✓ correcto")")
        return isModified
    }

    // MARK: - Detección 3: Sin App Store receipt
    // Las apps sideloaded no tienen recibo de compra

    static func hasNoAppStoreReceipt() -> Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: receiptURL.path) else {
            print("[DETECCIÓN 3] ❌ Sin App Store receipt — sideloaded o desarrollo")
            return true
        }
        print("[DETECCIÓN 3] ✓ Receipt presente")
        return false
    }

    // MARK: - Detección 4: Entitlements de desarrollo
    // Validar con: modify_entitlements.sh --preset desarrollo

    static func hasDevelopmentEntitlements() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return true
        }

        // "get-task-allow" está presente en builds de desarrollo
        // pero NO en builds del App Store
        let getTaskAllow = SecTaskCopyValueForEntitlement(
            task, "get-task-allow" as CFString, nil
        ) as? Bool ?? false

        // "beta-reports-active" también es de desarrollo
        let betaReports = SecTaskCopyValueForEntitlement(
            task, "beta-reports-active" as CFString, nil
        ) != nil

        let isDev = getTaskAllow || betaReports
        print("[DETECCIÓN 4] get-task-allow: \(getTaskAllow), beta-reports: \(betaReports) — \(isDev ? "❌ entitlements de desarrollo" : "✓ entitlements de producción")")
        return isDev
    }

    // MARK: - Detección 5: Perfil de aprovisionamiento embebido
    // Las apps del App Store NO llevan embedded.mobileprovision

    static func hasEmbeddedProvisioningProfile() -> Bool {
        if let profilePath = Bundle.main.path(
            forResource: "embedded",
            ofType: "mobileprovision"
        ) {
            let exists = FileManager.default.fileExists(atPath: profilePath)
            print("[DETECCIÓN 5] \(exists ? "❌ embedded.mobileprovision PRESENTE — sideloaded/desarrollo" : "✓ Sin perfil embebido")")
            return exists
        }
        print("[DETECCIÓN 5] ✓ Sin perfil embebido (normal en App Store)")
        return false
    }

    // MARK: - Detección 6: Imágenes dyld sospechosas cargadas
    // Validar con: inject_dylib.sh

    static func hasSuspiciousLoadedImages() -> Bool {
        let suspiciousPatterns = [
            "hook_license",     // dylib de prueba de CuySideStore
            "hook_network",     // dylib de prueba de CuySideStore
            "substrate",        // Cydia Substrate
            "substitute",       // Substitute
            "libhooker",        // libhooker
            "frida",            // Frida
            "cynject",          // Cycript
            "SSLKillSwitch",    // Bypass de pinning
            "MobileSubstrate",
            "TweakInject",
            "flexall",          // Flex patches
            "Shadow",           // Anti-detection bypass
            "A-Bypass",
            "Liberty"
        ]

        let count = _dyld_image_count()
        var found: [String] = []

        for i in 0..<count {
            guard let name = _dyld_get_image_name(i) else { continue }
            let lowercased = name.lowercased()
            for pattern in suspiciousPatterns where lowercased.contains(pattern.lowercased()) {
                found.append(name)
                break
            }
        }

        if found.isEmpty {
            print("[DETECCIÓN 6] ✓ No hay imágenes sospechosas cargadas (\(count) imágenes)")
            return false
        } else {
            print("[DETECCIÓN 6] ❌ Imágenes sospechosas: \(found)")
            return true
        }
    }

    // MARK: - Detección 7: Variables de entorno de inyección

    static func hasInjectionEnvironmentVariables() -> Bool {
        let suspiciousVars = [
            "DYLD_INSERT_LIBRARIES",
            "_MSSafeMode",
            "DYLD_PRINT_LIBRARIES",
            "OBJC_DISABLE_INITIALIZE_FORK_SAFETY"
        ]

        var found: [String] = []
        for varName in suspiciousVars {
            if getenv(varName) != nil {
                found.append(varName)
            }
        }

        if found.isEmpty {
            print("[DETECCIÓN 7] ✓ Sin variables de entorno de inyección")
            return false
        } else {
            print("[DETECCIÓN 7] ❌ Variables de inyección: \(found)")
            return true
        }
    }

    // MARK: - Detección 8: Debugger adjunto

    static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride

        let result = sysctl(&mib, 4, &info, &size, nil, 0)
        let attached = result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0

        print("[DETECCIÓN 8] Debugger: \(attached ? "❌ adjunto" : "✓ no adjunto")")
        return attached
    }

    // MARK: - Escaneo completo

    static func performFullScan() -> TamperReport {
        print("")
        print("═════════════════════════════════════════════════════════════")
        print("  CuyTestApp — Escaneo de tampering")
        print("═════════════════════════════════════════════════════════════")
        print("")

        let report = TamperReport(
            wrongTeamId: hasWrongTeamId(),
            modifiedBundleId: hasModifiedBundleId(),
            noAppStoreReceipt: hasNoAppStoreReceipt(),
            hasDevEntitlements: hasDevelopmentEntitlements(),
            hasEmbeddedProfile: hasEmbeddedProvisioningProfile(),
            suspiciousImages: hasSuspiciousLoadedImages(),
            injectionEnvVars: hasInjectionEnvironmentVariables(),
            debuggerAttached: isDebuggerAttached()
        )

        print("")
        print("─── RESULTADO ───")
        print("  Risk score: \(report.riskScore)/100")
        print("  Estado: \(report.isCompromised ? "❌ COMPROMETIDO" : "✓ LIMPIO")")
        print("")

        return report
    }
}