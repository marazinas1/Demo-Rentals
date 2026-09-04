ALTER TABLE public.room_status
  ADD COLUMN IF NOT EXISTS has_issue boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS issue_note text NOT NULL DEFAULT '';

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS language text;