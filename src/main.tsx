import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";

// Recuperação de chunk antigo / stale cache (Vite preload error)
// Faz reload único por sessão para evitar loop infinito.
if (typeof window !== "undefined") {
  const tryReloadOnce = () => {
    const KEY = "__chunk_reload_at";
    const last = Number(sessionStorage.getItem(KEY) || "0");
    if (Date.now() - last > 30_000) {
      sessionStorage.setItem(KEY, String(Date.now()));
      window.location.reload();
    }
  };

  window.addEventListener("vite:preloadError", (event) => {
    event.preventDefault?.();
    console.warn("[app] vite:preloadError — recarregando para limpar cache antigo.");
    tryReloadOnce();
  });

  window.addEventListener("error", (event) => {
    const msg = String(event?.message || "");
    if (
      msg.includes("Failed to fetch dynamically imported module") ||
      msg.includes("Importing a module script failed") ||
      msg.includes("error loading dynamically imported module")
    ) {
      console.warn("[app] dynamic import error — recarregando.");
      tryReloadOnce();
    }
  });

  window.addEventListener("unhandledrejection", (event) => {
    const msg = String(event?.reason?.message || event?.reason || "");
    if (
      msg.includes("Failed to fetch dynamically imported module") ||
      msg.includes("Importing a module script failed") ||
      msg.includes("error loading dynamically imported module")
    ) {
      console.warn("[app] unhandled dynamic import rejection — recarregando.");
      tryReloadOnce();
    }
  });
}

createRoot(document.getElementById("root")!).render(<App />);
