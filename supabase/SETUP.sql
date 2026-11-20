-- Run in the *existing* StudyPulse Supabase project's SQL Editor.
-- All commands preserve legacy StudyPulse tables and their data.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.sp2_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check(length(kind) between 1 and 50),
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS sp2_items_user_kind ON public.sp2_items(user_id,kind);
ALTER TABLE public.sp2_items ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.sp2_items TO authenticated;
DROP POLICY IF EXISTS sp2_items_per_user ON public.sp2_items;
CREATE POLICY sp2_items_per_user ON public.sp2_items FOR ALL TO authenticated
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

-- Fix for the 404 "Bucket not found" screen.
INSERT INTO storage.buckets(id,name,public,file_size_limit)
VALUES ('sp2_materials','sp2_materials',false,15728640)
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=15728640;

DROP POLICY IF EXISTS sp2_materials_read_own ON storage.objects;
CREATE POLICY sp2_materials_read_own ON storage.objects FOR SELECT TO authenticated
 USING(bucket_id='sp2_materials' AND (storage.foldername(name))[1]=(SELECT auth.uid())::text);
DROP POLICY IF EXISTS sp2_materials_upload_own ON storage.objects;
CREATE POLICY sp2_materials_upload_own ON storage.objects FOR INSERT TO authenticated
 WITH CHECK(bucket_id='sp2_materials' AND (storage.foldername(name))[1]=(SELECT auth.uid())::text);
DROP POLICY IF EXISTS sp2_materials_delete_own ON storage.objects;
CREATE POLICY sp2_materials_delete_own ON storage.objects FOR DELETE TO authenticated
 USING(bucket_id='sp2_materials' AND (storage.foldername(name))[1]=(SELECT auth.uid())::text);

NOTIFY pgrst,'reload schema';
SELECT id,name,public,file_size_limit FROM storage.buckets WHERE id='sp2_materials';
