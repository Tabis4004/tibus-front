import { isSupabaseAuth } from "@/lib/auth/config";
import HerculesCallback from "./HerculesCallback.tsx";
import SupabaseCallback from "./SupabaseCallback.tsx";

export default function AuthCallback() {
  return isSupabaseAuth() ? <SupabaseCallback /> : <HerculesCallback />;
}
