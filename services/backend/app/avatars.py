"""Small sanitized thumbnails in the existing DB; no public uploads or paid bucket."""
import base64
import binascii
from io import BytesIO
from PIL import Image, ImageOps, UnidentifiedImageError
from fastapi import HTTPException

def sanitize_avatar(value: str | None) -> str | None:
    if not value:
        return None
    try:
        raw = base64.b64decode(value, validate=True)
        if len(raw) > 200_000:
            raise ValueError('too large')
        with Image.open(BytesIO(raw)) as source:
            if source.format not in ('JPEG', 'PNG', 'WEBP') or source.width * source.height > 4_000_000:
                raise ValueError('unsupported image')
            source.load()
            thumb = ImageOps.fit(ImageOps.exif_transpose(source).convert('RGB'), (256, 256))
            output = BytesIO()
            # A fresh JPEG discards location, EXIF, comments and original file content.
            thumb.save(output, format='JPEG', quality=80)
            return base64.b64encode(output.getvalue()).decode('ascii')
    except (ValueError, binascii.Error, OSError, UnidentifiedImageError, Image.DecompressionBombError):
        raise HTTPException(422, 'Choose a JPEG, PNG or WebP photo under 200 KB and 4 megapixels.')
