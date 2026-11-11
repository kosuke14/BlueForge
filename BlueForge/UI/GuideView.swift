//
//  GuideView.swift
//  BlueForge
//
//  Self-contained guide for the A2DP state research flow on escape-capable
//  iOS (26.0–26.7.2 / 27.0–27.2): compatibility check, App Group setup,
//  probe, forge, and verification.
//

import SwiftUI

struct GuideView: View {
    var body: some View {
        Form {
            let compat = ExploitCompatibility.status()

            Section("0. 対応バージョン") {
                HStack {
                    Image(systemName: compat.supported ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .foregroundColor(compat.supported ? .green : .red)
                    Text(compat.title).font(.subheadline.weight(.semibold))
                }
                Text(compat.note)
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("1. App Group (エスケープの足場)") {
                Text("LiveContainer / SideStore 等で再署名する場合、ホスト IPA に App Group entitlement が付いていれば自動検出します (入力不要)。Free アカウントでは App Group を使えないため、有料署名または TrollStore が必要です。")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("2. 状態を測る (probe)") {
                NavigationLink("System probe を開く") { SystemProbeView() }
                Text("Bluetooth の状態は /var/wireless 系 (kernel 拒否) ではなく、コンテナ内を per-file extension で読みに行きます。デーモンコンテナの所有者は metadata plist で特定します。")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("3. 書き込みを実測する (CodecForge)") {
                NavigationLink("CodecForge を開く") { ForgeView() }
                Text("各ディレクトリでマーカーファイル生成/削除により WRITABLE を実測します。WRITABLE な場合のみ plist 編集が有効化され、書き込みはバックアップ/読み返し検証/自動復元付きです。")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("4. 効果の検証") {
                Text("コントロールセンターで Bluetooth を切替 → bluetoothd が状態を再読込 → 再 probe で差分を確認。全試行は forge_history.json に記録されます。")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("正直なスコープ") {
                Text("bluetoothd 内部へのコード注入 (A2DP SEP ネゴシエーション差し替え) は、脱獄ランタイムでのみ可能です。このアプリは脱獄検知時にその経路の設計 (docs/SANDBOX_A2DP.md) に接続しますが、エクスプロイトそのものは含みません。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("スタートガイド")
        .navigationBarTitleDisplayMode(.inline)
    }
}
