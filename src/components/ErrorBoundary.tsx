import { Component, type ErrorInfo, type ReactNode } from "react";
import { Button } from "@/components/ui/button.tsx";
import { isChunkLoadError } from "@/lib/lazy-with-retry.ts";

type Props = { children: ReactNode };
type State = { error: Error | null };

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("Tibus render error:", error, info.componentStack);
    if (isChunkLoadError(error) && !sessionStorage.getItem("tibus-chunk-reload")) {
      sessionStorage.setItem("tibus-chunk-reload", "1");
      window.location.reload();
    }
  }

  render() {
    if (this.state.error) {
      const chunkStale = isChunkLoadError(this.state.error);
      return (
        <div className="min-h-screen flex items-center justify-center p-6 bg-background">
          <div className="max-w-md w-full space-y-4 text-center">
            <h1 className="text-xl font-bold">Une erreur est survenue</h1>
            <p className="text-sm text-muted-foreground break-words">
              {chunkStale
                ? "Une nouvelle version de Tibus est disponible. Rechargez la page."
                : this.state.error.message}
            </p>
            <Button onClick={() => window.location.reload()}>Recharger</Button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
