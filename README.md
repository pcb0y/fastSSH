# FastSSH

A free, native macOS SSH client with built-in SFTP file manager.

---

## Why FastSSH?

I spent a long time looking for a good SSH client on macOS. Most of the decent ones charge money — some even require subscriptions for basic features. The free alternatives are either buggy, lack essential features, or haven't been updated in years.

So I built FastSSH: a fully native, completely free SSH tool that just works.

---

## Features

- **True PTY Terminal** — Full interactive shell with color support (256-color & true color), tab completion, and proper key handling
- **Built-in SFTP File Manager** — Dual-panel file browser with drag-and-drop, multi-file transfer, and directory upload/download
- **Connection Manager** — Save, organize, and quickly connect to your servers
- **Conflict Resolution** — Smart handling when files already exist (overwrite, rename, backup, or skip)
- **Native macOS App** — Pure Swift + SwiftUI, lightweight and fast
- **12 Languages** — English, 简体中文, 繁體中文, 日本語, 한국어, Español, Français, Deutsch, Português, Русский, العربية, हिन्दी

---

## Install

### Option 1: Download DMG (Recommended)

1. Download `FastSSH.dmg` from [Releases](https://github.com/pcb0y/fastSSH/releases)
2. Open the DMG file
3. Drag `FastSSH.app` to the `Applications` folder
4. Launch FastSSH from Launchpad or Applications

> Note: On first launch, macOS may show a security warning. Go to **System Settings → Privacy & Security** and click "Open Anyway".

### Option 2: Build from Source

Requirements: macOS 14+, Xcode Command Line Tools, libssh2

```bash
# Install dependencies
brew install libssh2 openssl

# Clone and build
git clone https://github.com/pcb0y/fastSSH.git
cd fastssh/FastSSH
swift build -c release

# Launch
open FastSSH.app
```

### Build DMG yourself

```bash
cd fastssh
mkdir -p dist/dmg_content
cp -R FastSSH/FastSSH.app dist/dmg_content/
ln -sf /Applications dist/dmg_content/Applications
hdiutil create -volname "FastSSH" -srcfolder dist/dmg_content -ov -format UDZO dist/FastSSH.dmg
```

---

## Screenshots

<!-- Add screenshots here -->

---

## License

MIT — Free to use, free to modify, free forever.

---

---

# FastSSH

一款免费的 macOS 原生 SSH 客户端，内置 SFTP 文件管理器。

---

## 为什么做 FastSSH？

在网上找了很久 macOS 上好用的 SSH 工具，发现稍微能用的都要收费，有的甚至按月订阅才能用基本功能。免费的要么 bug 一堆，要么功能缺失，要么早就没人维护了。

既然找不到满意的，那就自己写一个。FastSSH 完全免费，原生开发，没有任何限制。

---

## 功能特性

- **真正的 PTY 终端** — 完整交互式 Shell，支持 256 色和真彩色，Tab 补全、快捷键全部正常工作
- **内置 SFTP 文件管理器** — 双栏文件浏览器，支持拖放、多文件传输、目录上传下载
- **连接管理** — 保存、分组、快速连接你的服务器
- **冲突处理** — 文件已存在时智能提示（覆盖、重命名、备份、跳过）
- **原生 macOS 应用** — 纯 Swift + SwiftUI 开发，轻量快速
- **12 种语言** — 中文、英文、日文、韩文、西班牙文、法文、德文、葡萄牙文、俄文、阿拉伯文、印地文

---

## 安装

### 方式一：下载 DMG 安装包（推荐）

1. 从 [Releases](https://github.com/pcb0y/fastSSH/releases) 下载 `FastSSH.dmg`
2. 双击打开 DMG 文件
3. 将 `FastSSH.app` 拖入 `Applications` 文件夹
4. 从启动台或应用程序中打开 FastSSH

> 注意：首次启动时 macOS 可能会弹出安全提示，请前往 **系统设置 → 隐私与安全性**，点击"仍要打开"。

### 方式二：从源码编译

环境要求：macOS 14+、Xcode 命令行工具、libssh2

```bash
# 安装依赖
brew install libssh2 openssl

# 克隆并编译
git clone https://github.com/pcb0y/fastSSH.git
cd fastssh/FastSSH
swift build -c release

# 启动
open FastSSH.app
```

### 自行打包 DMG

```bash
cd fastssh
mkdir -p dist/dmg_content
cp -R FastSSH/FastSSH.app dist/dmg_content/
ln -sf /Applications dist/dmg_content/Applications
hdiutil create -volname "FastSSH" -srcfolder dist/dmg_content -ov -format UDZO dist/FastSSH.dmg
```

---

## 许可证

MIT — 免费使用，免费修改，永远免费。

---

---

# FastSSH

macOS用の無料ネイティブSSHクライアント。SFTPファイルマネージャー内蔵。

---

## なぜFastSSH？

macOSで使えるSSHクライアントを探しましたが、まともなものはほとんど有料でした。無料のものはバグが多かったり、機能が不足していたり、更新が止まっていたりします。

だから自分で作りました。FastSSHは完全無料で、ネイティブ開発、制限なしです。

---

## 機能

- **本物のPTYターミナル** — 256色・トゥルーカラー対応、Tab補完、ショートカットキー完全対応
- **内蔵SFTPファイルマネージャー** — デュアルパネル、ドラッグ＆ドロップ、複数ファイル・ディレクトリ転送
- **接続管理** — サーバー設定の保存・グループ化・クイック接続
- **競合解決** — ファイル重複時の処理選択（上書き・リネーム・バックアップ・スキップ）
- **ネイティブmacOSアプリ** — Pure Swift + SwiftUI、軽量高速
- **12言語対応**

---

## インストール

### 方法1：DMGダウンロード（推奨）

1. [Releases](https://github.com/pcb0y/fastSSH/releases) から `FastSSH.dmg` をダウンロード
2. DMGファイルを開く
3. `FastSSH.app` を `Applications` フォルダにドラッグ
4. LaunchpadまたはApplicationsからFastSSHを起動

### 方法2：ソースからビルド

```bash
brew install libssh2 openssl
git clone https://github.com/pcb0y/fastSSH.git
cd fastssh/FastSSH
swift build -c release
open FastSSH.app
```

---

## ライセンス

MIT — 無料で使用、無料で改変、永久に無料。

---

---

# FastSSH

Un cliente SSH nativo y gratuito para macOS con administrador de archivos SFTP integrado.

---

## ¿Por qué FastSSH?

Busqué durante mucho tiempo un buen cliente SSH en macOS. La mayoría de los decentes cobran dinero — algunos incluso requieren suscripciones para funciones básicas. Las alternativas gratuitas tienen errores, carecen de funciones esenciales o no se han actualizado en años.

Así que construí FastSSH: una herramienta SSH completamente nativa, completamente gratuita, que simplemente funciona.

---

## Características

- **Terminal PTY real** — Shell interactivo completo con soporte de color (256 colores y color verdadero)
- **Administrador de archivos SFTP integrado** — Panel dual con arrastrar y soltar, transferencia múltiple
- **Gestor de conexiones** — Guarda, organiza y conéctate rápidamente a tus servidores
- **Resolución de conflictos** — Manejo inteligente cuando los archivos ya existen
- **App nativa de macOS** — Swift + SwiftUI puro, ligera y rápida
- **12 idiomas**

---

## Instalación

### Opción 1: Descargar DMG (Recomendado)

1. Descarga `FastSSH.dmg` de [Releases](https://github.com/pcb0y/fastSSH/releases)
2. Abre el archivo DMG
3. Arrastra `FastSSH.app` a la carpeta `Applications`
4. Abre FastSSH desde Launchpad o Aplicaciones

### Opción 2: Compilar desde el código fuente

```bash
brew install libssh2 openssl
git clone https://github.com/pcb0y/fastSSH.git
cd fastssh/FastSSH
swift build -c release
open FastSSH.app
```

---

## Licencia

MIT — Gratis para usar, gratis para modificar, gratis para siempre.

---

---

# FastSSH

Un client SSH natif et gratuit pour macOS avec gestionnaire de fichiers SFTP intégré.

---

## Pourquoi FastSSH ?

J'ai longtemps cherché un bon client SSH sur macOS. La plupart des clients corrects sont payants — certains exigent même un abonnement pour des fonctions de base. Les alternatives gratuites sont soit buguées, soit incomplètes, soit abandonnées.

Alors j'ai créé FastSSH : un outil SSH entièrement natif, entièrement gratuit, qui fonctionne tout simplement.

---

## Fonctionnalités

- **Vrai terminal PTY** — Shell interactif complet avec support couleur (256 couleurs et couleur vraie)
- **Gestionnaire de fichiers SFTP intégré** — Double panneau avec glisser-déposer et transfert multiple
- **Gestionnaire de connexions** — Sauvegardez, organisez et connectez-vous rapidement
- **Résolution de conflits** — Gestion intelligente des fichiers existants
- **App macOS native** — Swift + SwiftUI pur, légère et rapide
- **12 langues**

---

## Installation

### Option 1 : Télécharger le DMG (Recommandé)

1. Téléchargez `FastSSH.dmg` depuis [Releases](https://github.com/pcb0y/fastSSH/releases)
2. Ouvrez le fichier DMG
3. Glissez `FastSSH.app` dans le dossier `Applications`
4. Lancez FastSSH depuis le Launchpad ou Applications

### Option 2 : Compiler depuis les sources

```bash
brew install libssh2 openssl
git clone https://github.com/pcb0y/fastSSH.git
cd fastssh/FastSSH
swift build -c release
open FastSSH.app
```

---

## Licence

MIT — Gratuit à utiliser, gratuit à modifier, gratuit pour toujours.
