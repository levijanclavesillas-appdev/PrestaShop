<?php
$zip = new ZipArchive();
$filename = __DIR__ . '/xenditpay.zip';

if (file_exists($filename)) {
    unlink($filename);
}

if ($zip->open($filename, ZipArchive::CREATE) !== TRUE) {
    exit("Cannot open <$filename>\n");
}

$dir = __DIR__ . '/modules/xenditpay';
$files = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($dir),
    RecursiveIteratorIterator::LEAVES_ONLY
);

foreach ($files as $name => $file) {
    if (!$file->isDir()) {
        $filePath = $file->getRealPath();
        // Get relative path for zip: xenditpay/...
        $relativePath = 'xenditpay/' . substr($filePath, strlen($dir) + 1);
        // Replace Windows backslashes with forward slashes for zip compatibility
        $relativePath = str_replace('\\', '/', $relativePath);
        $zip->addFile($filePath, $relativePath);
    }
}

$zip->close();
echo "Zip created successfully!";
