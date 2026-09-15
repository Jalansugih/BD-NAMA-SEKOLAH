-- RajaKas.id - FIX STORAGE BUKTI PENGELUARAN (MULTI-TENANT)
-- Jalankan sekali di Supabase SQL Editor.
-- Frontend menyimpan file pada: <organization_id>/<timestamp-random>.ext
-- RLS memastikan folder pertama harus sama dengan organisasi user login.

BEGIN;

INSERT INTO storage.buckets (id, name, public)
VALUES ('bukti-pengeluaran', 'bukti-pengeluaran', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Hapus policy lama yang memakai user UUID atau nama policy versi sebelumnya.
DROP POLICY IF EXISTS "Bukti Pengeluaran - baca publik" ON storage.objects;
DROP POLICY IF EXISTS "Bukti Pengeluaran - upload user login" ON storage.objects;
DROP POLICY IF EXISTS "Bukti Pengeluaran - update user login" ON storage.objects;
DROP POLICY IF EXISTS "Bukti Pengeluaran - delete user login" ON storage.objects;
DROP POLICY IF EXISTS "Tenant bukti - baca" ON storage.objects;
DROP POLICY IF EXISTS "Tenant bukti - upload" ON storage.objects;
DROP POLICY IF EXISTS "Tenant bukti - update" ON storage.objects;
DROP POLICY IF EXISTS "Tenant bukti - delete" ON storage.objects;
DROP POLICY IF EXISTS rk_bukti_read ON storage.objects;
DROP POLICY IF EXISTS rk_bukti_insert ON storage.objects;
DROP POLICY IF EXISTS rk_bukti_update ON storage.objects;
DROP POLICY IF EXISTS rk_bukti_delete ON storage.objects;

CREATE POLICY rajas_bukti_read
ON storage.objects
FOR SELECT
TO public
USING (
  bucket_id = 'bukti-pengeluaran'
);

CREATE POLICY rajas_bukti_insert
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'bukti-pengeluaran'
  AND (storage.foldername(name))[1] = public.get_auth_org_id()::text
);

CREATE POLICY rajas_bukti_update
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'bukti-pengeluaran'
  AND (storage.foldername(name))[1] = public.get_auth_org_id()::text
)
WITH CHECK (
  bucket_id = 'bukti-pengeluaran'
  AND (storage.foldername(name))[1] = public.get_auth_org_id()::text
);

CREATE POLICY rajas_bukti_delete
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'bukti-pengeluaran'
  AND (storage.foldername(name))[1] = public.get_auth_org_id()::text
);

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Verifikasi:
SELECT id, name, public
FROM storage.buckets
WHERE id = 'bukti-pengeluaran';
