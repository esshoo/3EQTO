#!/usr/bin/env python3
"""3EQTO Quality R1 checks. Portable Swift tests run on Linux and macOS.
Apple SIMD wall-assignment tests run on macOS CI. Not an iOS device test.
"""
from pathlib import Path
import plistlib
import platform
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'RoomSurveyElectrical'

def check(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit('FAIL: ' + message)
    print('PASS: ' + message, flush=True)

def read(name: str) -> str:
    return (APP / name).read_text(encoding='utf-8')

def run_swift(sources: list[Path], name: str, directory: Path) -> None:
    binary = directory / name
    subprocess.run(['swiftc', '-swift-version', '5', *map(str, sources), '-o', str(binary)], check=True, cwd=ROOT)
    subprocess.run([str(binary)], check=True, cwd=ROOT)

def main() -> None:
    check(shutil.which('swiftc') is not None, 'Swift compiler available')
    with tempfile.TemporaryDirectory(prefix='3eqto-check-') as directory:
        run_swift([APP / 'QTOQualityCore.swift', ROOT / 'Tools/test-qto-quality.swift'], 'quality', Path(directory))
        if platform.system() == 'Darwin':
            run_swift([APP / 'QTOQualityCore.swift', APP / 'QTOTakeoffGeometry.swift', ROOT / 'Tools/test-qto-wall-assignment.swift'], 'walls', Path(directory))
        else:
            print('SKIP: Apple SIMD assignment runtime tests require macOS; CI runs them before Xcode.', flush=True)
    models = read('Models.swift')
    check('var polygonCorners: [[Float]]?' in models and 'var parentWallID: UUID?' in models, 'new stored fields remain optional for legacy projects')
    check('surface.polygonCorners' in models and 'surface.parentIdentifier' in models, 'RoomPlan captures footprint and parent metadata')
    check('QTOQualityMath.unionArea' in models and 'QTOTakeoffGeometry.assignOpening' in models, 'takeoff uses clipping, assignment and union')
    check(read('RoomProjectGeometryMerger.swift').count('polygonCorners:') == 3, 'all three floor transformation paths preserve native polygons')
    for filename in ['DXFExporter.swift', 'PNGExporter.swift', 'LayeredPDFExporter.swift', 'RoomViewer.swift', 'ExportCenter.swift']:
        check('ExportGeometry.floorCorners(floor)' in read(filename), filename + ' uses shared footprint')
    check('makePolygonFloorNodes' in read('GLBExporter.swift'), 'GLB triangulates native floor footprints')
    check('let project: RoomProject' in read('SnapshotRoom3DView.swift') and 'preserveCamera' in read('SnapshotRoom3DView.swift'), 'snapshot viewer tracks content and preserves camera')
    capture = read('RoomCaptureModel.swift')
    check('guard gate.shouldDeliver(at: frame.timestamp)' in capture and 'defer { gate.completeDelivery() }' in capture, 'AR frame coalescing completes even after weak-owner release')
    check('stop(pauseARSession: pauseCameraImmediately)' in capture, 'background and thermal stops pause the camera session')
    check('QTOFrameBudget.referenceImageInterval' in capture, 'reference images obey thermal/power budget')
    for filename in ['SnapshotRoom3DView.swift', 'RoomViewer.swift', 'ElectricalARView.swift', 'AdaptivePhotographicWallScanView.swift']:
        check('performance.stop()' in read(filename), filename + ' detaches rendering observers')
    check('qualitySheet()' in read('ExportCenter.swift'), 'quality warnings exported to XLSX')
    check('QTOQuantityQualityView' in read('ContentView.swift'), 'takeoff shows measurement qualifications')
    info = plistlib.loads((ROOT / 'Support/Info.plist').read_bytes())
    check(info['CFBundleDisplayName'] == '3EQTO', 'new display name')
    constants = read('ThreeEStorageConstants.swift')
    for value in ['com.essam.3E.roomelectrical', 'Apps/RoomElectrical', 'appKey = "roomElectrical"', 'urlScheme = "electrical"']:
        check(value in constants, 'stable identity retained: ' + value)
    check('exportedAs: "com.3essam.3eroomelectrical.project"' in read('ProjectPackage.swift'), 'project file identity retained')
    print('3EQTO Quality R1 checks: PASS (full iOS build and device acceptance remain separate).', flush=True)

if __name__ == '__main__':
    main()
