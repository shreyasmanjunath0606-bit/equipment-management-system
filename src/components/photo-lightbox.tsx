"use client";

import { useRef } from "react";
import { X, ZoomIn } from "lucide-react";

/** Thumbnail that opens the full photo in a native <dialog> (Esc / backdrop click closes). */
export default function PhotoLightbox({ src, alt }: { src: string; alt: string }) {
  const ref = useRef<HTMLDialogElement>(null);
  return (
    <>
      <button type="button" onClick={() => ref.current?.showModal()} className="group relative mt-3 block overflow-hidden rounded-lg border">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={src} alt={alt} className="h-36 w-auto max-w-full object-cover transition group-hover:scale-[1.02]" loading="lazy" />
        <span className="absolute inset-0 flex items-center justify-center bg-black/0 text-white opacity-0 transition group-hover:bg-black/30 group-hover:opacity-100">
          <ZoomIn className="size-5" />
        </span>
      </button>
      <dialog
        ref={ref}
        onClick={(e) => { if (e.target === ref.current) ref.current?.close(); }}
        className="m-auto max-h-[90vh] max-w-[92vw] rounded-xl bg-transparent p-0 backdrop:bg-black/80"
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={src} alt={alt} className="max-h-[90vh] max-w-[92vw] rounded-xl object-contain" />
        <button onClick={() => ref.current?.close()} aria-label="Close photo" className="absolute right-3 top-3 rounded-full bg-black/60 p-1.5 text-white hover:bg-black/80">
          <X className="size-4" />
        </button>
      </dialog>
    </>
  );
}
