import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / 'ThreeOneOSFive/helpers/FeaturePatchService.swift'
VIEW = ROOT / 'ThreeOneOSFive/views/FeaturesView.swift'

class PatchAvatarIsolationTests(unittest.TestCase):
    def test_patch_image_cache_and_dirs_declared(self):
        text = SERVICE.read_text(encoding='utf-8')
        self.assertIn('@Published private(set) var patchImageCache: [Int: UIImage] = [:]', text)
        self.assertIn('private let patchImagesDir: URL', text)
        self.assertIn('func preloadPatchImages()', text)
        self.assertIn('func downloadPatchImageIfNeeded(_ patch: PatchItem', text)

    def test_cached_image_prioritizes_patch_avatar_over_category(self):
        text = SERVICE.read_text(encoding='utf-8')
        cached_impl = text[text.index('func cachedImage(for patch: PatchItem)'):]
        cached_impl = cached_impl[:cached_impl.index('// MARK: - NovaX Native Patch Menu')]
        
        # Patch-specific cache check comes before category fallback
        patch_check = cached_impl.index('patchImageCache[patch.id]')
        cat_check = cached_impl.index('categoryImage(for: patch.categoryId)')
        self.assertLess(patch_check, cat_check, "Patch avatar must take priority over category fallback")

    def test_sync_downloads_and_preloads_patch_images(self):
        text = SERVICE.read_text(encoding='utf-8')
        self.assertIn('preloadPatchImages()', text)
        self.assertIn('await self.downloadPatchImageIfNeeded(patch)', text)

    def test_features_view_preloads_patch_images(self):
        text = VIEW.read_text(encoding='utf-8')
        self.assertIn('service.preloadPatchImages()', text)

if __name__ == '__main__':
    unittest.main()
