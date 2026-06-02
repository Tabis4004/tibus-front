import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useParams, useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import {
  ArrowLeftIcon,
  MapPinIcon,
  TrainFrontIcon,
  BusIcon,
  RouteIcon,
  CalendarIcon,
  TicketIcon,
  PlusIcon,
  Trash2Icon,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Label } from "@/components/ui/label.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent } from "@/components/ui/empty.tsx";
import { toast } from "sonner";
import { cn } from "@/lib/utils.ts";
import SeatPicker from "@/components/seat-picker.tsx";

type TabId = "stations" | "buses" | "routes" | "trips" | "tickets";

const TABS: { id: TabId; icon: typeof MapPinIcon; labelKey: string }[] = [
  { id: "stations", icon: MapPinIcon, labelKey: "Stations" },
  { id: "buses", icon: BusIcon, labelKey: "Buses" },
  { id: "routes", icon: RouteIcon, labelKey: "Routes" },
  { id: "trips", icon: CalendarIcon, labelKey: "Trips" },
  { id: "tickets", icon: TicketIcon, labelKey: "Sell Tickets" },
];

export default function AdminCompanyManager() {
  const { lng, companyId } = useParams<{ lng: string; companyId: string }>();
  const navigate = useNavigate();
  const { t } = useTranslation("common");
  const [tab, setTab] = useState<TabId>("stations");

  const company = useQuery(api.companies.getCompanyById, companyId ? { companyId: companyId as Id<"companies"> } : "skip");

  if (!companyId) return null;
  const cid = companyId as Id<"companies">;

  // Loading state while company data is fetched
  if (company === undefined) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-8 space-y-6">
        <div className="flex items-center gap-3">
          <Skeleton className="h-8 w-16 rounded-lg" />
          <div className="space-y-2">
            <Skeleton className="h-6 w-48" />
            <Skeleton className="h-4 w-32" />
          </div>
        </div>
        <Skeleton className="h-12 w-full rounded-xl" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto px-4 py-8 space-y-6">
      {/* Header */}
      <div className="flex items-center gap-3">
        <Button
          variant="ghost"
          size="sm"
          className="cursor-pointer"
          onClick={() => navigate(`/${lng}/admin`)}
        >
          <ArrowLeftIcon className="w-4 h-4 mr-1" /> Back
        </Button>
        <div>
          <h1 className="text-xl font-extrabold tracking-tight">
            {company?.name ?? "Company"}
          </h1>
          <p className="text-sm text-muted-foreground">Manage resources for this company</p>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 overflow-x-auto bg-muted p-1 rounded-xl">
        {TABS.map(({ id, icon: Icon, labelKey }) => (
          <button
            key={id}
            onClick={() => setTab(id)}
            className={cn(
              "flex items-center justify-center gap-1.5 py-2 px-3 rounded-lg text-sm font-medium transition-colors cursor-pointer whitespace-nowrap",
              tab === id
                ? "bg-background shadow-sm text-foreground"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            <Icon className="w-4 h-4" />
            <span className="hidden sm:inline">{labelKey}</span>
          </button>
        ))}
      </div>

      {tab === "stations" && <StationsTab companyId={cid} />}
      {tab === "buses" && <BusesTab companyId={cid} />}
      {tab === "routes" && <RoutesTab companyId={cid} />}
      {tab === "trips" && <TripsTab companyId={cid} />}
      {tab === "tickets" && <TicketsTab companyId={cid} />}
    </div>
  );
}

// ─── Stations Tab ───────────────────────────────────────────────────────────

function StationsTab({ companyId }: { companyId: Id<"companies"> }) {
  const stations = useQuery(api.adminManage.listStations, { companyId });
  const cities = useQuery(api.geography.listCities, {});
  const createStation = useMutation(api.adminManage.createStation);
  const deleteStation = useMutation(api.adminManage.deleteStation);
  const [showAdd, setShowAdd] = useState(false);
  const [name, setName] = useState("");
  const [address, setAddress] = useState("");
  const [cityId, setCityId] = useState("");
  const [lat, setLat] = useState("");
  const [lng, setLng] = useState("");
  const [loading, setLoading] = useState(false);

  const handleAdd = async () => {
    if (!name.trim() || !address.trim() || !cityId) return;
    setLoading(true);
    const latitude = lat ? parseFloat(lat) : undefined;
    const longitude = lng ? parseFloat(lng) : undefined;
    try {
      await createStation({
        companyId,
        cityId: cityId as Id<"cities">,
        name: name.trim(),
        address: address.trim(),
        latitude: isNaN(latitude as number) ? undefined : latitude,
        longitude: isNaN(longitude as number) ? undefined : longitude,
      });
      toast.success("Station added!");
      setName("");
      setAddress("");
      setCityId("");
      setLat("");
      setLng("");
      setShowAdd(false);
    } catch {
      toast.error("Failed to add station");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base">Stations</CardTitle>
          <Button size="sm" className="cursor-pointer" onClick={() => setShowAdd(true)}>
            <PlusIcon className="w-4 h-4 mr-1" /> Add Station
          </Button>
        </div>
      </CardHeader>
      <CardContent>
        {stations === undefined ? (
          <div className="space-y-2">
            {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-12 w-full rounded-xl" />)}
          </div>
        ) : stations.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon"><TrainFrontIcon /></EmptyMedia>
              <EmptyTitle>No stations yet</EmptyTitle>
              <EmptyDescription>Add cities first (in Geography tab), then create stations</EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <div className="space-y-1">
            {stations.map((s) => (
              <div key={s._id} className="flex items-center gap-3 p-3 rounded-xl hover:bg-muted/50">
                <TrainFrontIcon className="w-4 h-4 text-primary shrink-0" />
                <div className="flex-1 min-w-0">
                  <div className="font-medium text-sm">{s.name}</div>
                  <div className="text-xs text-muted-foreground">{s.location?.city}, {s.location?.country} — {s.address}</div>
                </div>
                <Badge variant={s.isActive ? "default" : "secondary"} className="text-[10px]">{s.isActive ? "Active" : "Inactive"}</Badge>
                <Button variant="ghost" size="sm" className="cursor-pointer h-7 text-xs text-destructive" onClick={() => deleteStation({ stationId: s._id }).then(() => toast.success("Station deleted")).catch(() => toast.error("Failed"))}>
                  <Trash2Icon className="w-3 h-3" />
                </Button>
              </div>
            ))}
          </div>
        )}
      </CardContent>

      <Dialog open={showAdd} onOpenChange={setShowAdd}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Add Station</DialogTitle>
            <DialogDescription>Create a station linked to a city</DialogDescription>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <div className="space-y-1.5">
              <Label>City *</Label>
              <Select value={cityId} onValueChange={setCityId}>
                <SelectTrigger><SelectValue placeholder="Select city" /></SelectTrigger>
                <SelectContent>
                  {cities?.map((c) => (
                    <SelectItem key={c._id} value={c._id}>{c.name}, {c.countryName}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Station Name *</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Gare Routière Bonabéri" />
            </div>
            <div className="space-y-1.5">
              <Label>Address *</Label>
              <Input value={address} onChange={(e) => setAddress(e.target.value)} placeholder="e.g. Rue de la Gare, Douala" />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Latitude</Label>
                <Input type="number" step="any" value={lat} onChange={(e) => setLat(e.target.value)} placeholder="e.g. 6.1725" />
              </div>
              <div className="space-y-1.5">
                <Label>Longitude</Label>
                <Input type="number" step="any" value={lng} onChange={(e) => setLng(e.target.value)} placeholder="e.g. 1.2314" />
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setShowAdd(false)} className="cursor-pointer">Cancel</Button>
            <Button onClick={handleAdd} disabled={loading || !name.trim() || !address.trim() || !cityId} className="cursor-pointer">
              {loading ? "Adding..." : "Add"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}

// ─── Buses Tab ──────────────────────────────────────────────────────────────

function BusesTab({ companyId }: { companyId: Id<"companies"> }) {
  const buses = useQuery(api.adminManage.listBuses, { companyId });
  const create = useMutation(api.adminManage.createBus);
  const remove = useMutation(api.adminManage.deleteBus);
  const [showAdd, setShowAdd] = useState(false);
  const [name, setName] = useState("");
  const [plate, setPlate] = useState("");
  const [capacity, setCapacity] = useState("40");
  const [busType, setBusType] = useState("standard");
  const [loading, setLoading] = useState(false);

  const handleAdd = async () => {
    if (!name.trim() || !plate.trim()) return;
    setLoading(true);
    try {
      await create({ companyId, name: name.trim(), plateNumber: plate.trim(), capacity: Number(capacity) || 40, busType });
      toast.success("Bus added!");
      setName("");
      setPlate("");
      setCapacity("40");
      setShowAdd(false);
    } catch {
      toast.error("Failed to add bus");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base">Buses</CardTitle>
          <Button size="sm" className="cursor-pointer" onClick={() => setShowAdd(true)}>
            <PlusIcon className="w-4 h-4 mr-1" /> Add Bus
          </Button>
        </div>
      </CardHeader>
      <CardContent>
        {buses === undefined ? (
          <div className="space-y-2">
            {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-12 w-full rounded-xl" />)}
          </div>
        ) : buses.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon"><BusIcon /></EmptyMedia>
              <EmptyTitle>No buses yet</EmptyTitle>
              <EmptyDescription>Add buses to this company's fleet</EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <div className="space-y-1">
            {buses.map((b) => (
              <div key={b._id} className="flex items-center gap-3 p-3 rounded-xl hover:bg-muted/50">
                <BusIcon className="w-4 h-4 text-primary shrink-0" />
                <div className="flex-1 min-w-0">
                  <div className="font-medium text-sm">{b.name}</div>
                  <div className="text-xs text-muted-foreground">{b.plateNumber} — {b.capacity} seats — {b.busType}</div>
                </div>
                <Badge variant={b.isActive ? "default" : "secondary"} className="text-[10px]">{b.isActive ? "Active" : "Inactive"}</Badge>
                <Button variant="ghost" size="sm" className="cursor-pointer h-7 text-xs text-destructive" onClick={() => remove({ busId: b._id }).then(() => toast.success("Bus removed")).catch(() => toast.error("Failed"))}>
                  <Trash2Icon className="w-3 h-3" />
                </Button>
              </div>
            ))}
          </div>
        )}
      </CardContent>

      <Dialog open={showAdd} onOpenChange={setShowAdd}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Add Bus</DialogTitle>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <div className="space-y-1.5">
              <Label>Bus Name *</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Luxury Coach A1" />
            </div>
            <div className="space-y-1.5">
              <Label>Plate Number *</Label>
              <Input value={plate} onChange={(e) => setPlate(e.target.value)} placeholder="e.g. LT-1234-CM" />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Capacity</Label>
                <Input type="number" value={capacity} onChange={(e) => setCapacity(e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label>Type</Label>
                <Select value={busType} onValueChange={setBusType}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="standard">Standard</SelectItem>
                    <SelectItem value="luxury">Luxury</SelectItem>
                    <SelectItem value="mini">Mini Bus</SelectItem>
                    <SelectItem value="vip">VIP</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setShowAdd(false)} className="cursor-pointer">Cancel</Button>
            <Button onClick={handleAdd} disabled={loading || !name.trim() || !plate.trim()} className="cursor-pointer">
              {loading ? "Adding..." : "Add"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}

// ─── Routes Tab ─────────────────────────────────────────────────────────────

function RoutesTab({ companyId }: { companyId: Id<"companies"> }) {
  const routes = useQuery(api.adminManage.listRoutes, { companyId });
  const stations = useQuery(api.adminManage.listStations, { companyId });
  const create = useMutation(api.adminManage.createRoute);
  const remove = useMutation(api.adminManage.deleteRoute);
  const [showAdd, setShowAdd] = useState(false);
  const [originId, setOriginId] = useState("");
  const [destId, setDestId] = useState("");
  const [duration, setDuration] = useState("120");
  const [loading, setLoading] = useState(false);

  const handleAdd = async () => {
    if (!originId || !destId || originId === destId) return;
    setLoading(true);
    try {
      await create({
        companyId,
        originStationId: originId as Id<"stations">,
        destinationStationId: destId as Id<"stations">,
        estimatedDurationMinutes: Number(duration) || 120,
      });
      toast.success("Route created!");
      setOriginId("");
      setDestId("");
      setShowAdd(false);
    } catch {
      toast.error("Failed to create route");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base">Routes</CardTitle>
          <Button size="sm" className="cursor-pointer" onClick={() => setShowAdd(true)}>
            <PlusIcon className="w-4 h-4 mr-1" /> Add Route
          </Button>
        </div>
      </CardHeader>
      <CardContent>
        {routes === undefined ? (
          <div className="space-y-2">
            {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-12 w-full rounded-xl" />)}
          </div>
        ) : routes.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon"><RouteIcon /></EmptyMedia>
              <EmptyTitle>No routes yet</EmptyTitle>
              <EmptyDescription>Add stations first, then create routes between them</EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <div className="space-y-1">
            {routes.map((r) => (
              <div key={r._id} className="flex items-center gap-3 p-3 rounded-xl hover:bg-muted/50">
                <RouteIcon className="w-4 h-4 text-primary shrink-0" />
                <div className="flex-1 min-w-0">
                  <div className="font-medium text-sm">
                    {r.origin?.name ?? "?"} → {r.destination?.name ?? "?"}
                  </div>
                  <div className="text-xs text-muted-foreground">
                    {r.originLoc?.city} → {r.destLoc?.city} — {r.estimatedDurationMinutes} min
                  </div>
                </div>
                <Badge variant={r.isActive ? "default" : "secondary"} className="text-[10px]">{r.isActive ? "Active" : "Inactive"}</Badge>
                <Button variant="ghost" size="sm" className="cursor-pointer h-7 text-xs text-destructive" onClick={() => remove({ routeId: r._id }).then(() => toast.success("Route deleted")).catch(() => toast.error("Failed"))}>
                  <Trash2Icon className="w-3 h-3" />
                </Button>
              </div>
            ))}
          </div>
        )}
      </CardContent>

      <Dialog open={showAdd} onOpenChange={setShowAdd}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Add Route</DialogTitle>
            <DialogDescription>Connect two stations</DialogDescription>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <div className="space-y-1.5">
              <Label>Origin Station *</Label>
              <Select value={originId} onValueChange={setOriginId}>
                <SelectTrigger><SelectValue placeholder="Select origin" /></SelectTrigger>
                <SelectContent>
                  {stations?.map((s) => (
                    <SelectItem key={s._id} value={s._id}>{s.name} ({s.location?.city})</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Destination Station *</Label>
              <Select value={destId} onValueChange={setDestId}>
                <SelectTrigger><SelectValue placeholder="Select destination" /></SelectTrigger>
                <SelectContent>
                  {stations?.filter((s) => s._id !== originId).map((s) => (
                    <SelectItem key={s._id} value={s._id}>{s.name} ({s.location?.city})</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Duration (minutes)</Label>
              <Input type="number" value={duration} onChange={(e) => setDuration(e.target.value)} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setShowAdd(false)} className="cursor-pointer">Cancel</Button>
            <Button onClick={handleAdd} disabled={loading || !originId || !destId || originId === destId} className="cursor-pointer">
              {loading ? "Creating..." : "Create Route"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}

// ─── Trips Tab ──────────────────────────────────────────────────────────────

function TripsTab({ companyId }: { companyId: Id<"companies"> }) {
  const trips = useQuery(api.adminManage.listTrips, { companyId });
  const routes = useQuery(api.adminManage.listRoutes, { companyId });
  const buses = useQuery(api.adminManage.listBuses, { companyId });
  const create = useMutation(api.adminManage.createTrip);
  const remove = useMutation(api.adminManage.deleteTrip);
  const updateStatus = useMutation(api.adminManage.updateTripStatus);
  const [showAdd, setShowAdd] = useState(false);
  const [routeId, setRouteId] = useState("");
  const [busId, setBusId] = useState("");
  const [departure, setDeparture] = useState("");
  const [arrival, setArrival] = useState("");
  const [price, setPrice] = useState("5000");
  const [currency, setCurrency] = useState("XAF");
  const [loading, setLoading] = useState(false);

  const handleAdd = async () => {
    if (!routeId || !busId || !departure || !arrival) return;
    setLoading(true);
    try {
      await create({
        companyId,
        routeId: routeId as Id<"routes">,
        busId: busId as Id<"buses">,
        departureTime: new Date(departure).toISOString(),
        arrivalTime: new Date(arrival).toISOString(),
        priceAmount: Number(price) || 5000,
        currency,
      });
      toast.success("Trip scheduled!");
      setRouteId("");
      setBusId("");
      setDeparture("");
      setArrival("");
      setShowAdd(false);
    } catch {
      toast.error("Failed to schedule trip");
    } finally {
      setLoading(false);
    }
  };

  const statusColors: Record<string, string> = {
    scheduled: "bg-blue-500/10 text-blue-600",
    active: "bg-green-500/10 text-green-600",
    completed: "bg-muted text-muted-foreground",
    cancelled: "bg-red-500/10 text-red-600",
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base">Trips</CardTitle>
          <Button size="sm" className="cursor-pointer" onClick={() => setShowAdd(true)}>
            <PlusIcon className="w-4 h-4 mr-1" /> Schedule Trip
          </Button>
        </div>
      </CardHeader>
      <CardContent>
        {trips === undefined ? (
          <div className="space-y-2">
            {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-14 w-full rounded-xl" />)}
          </div>
        ) : trips.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon"><CalendarIcon /></EmptyMedia>
              <EmptyTitle>No trips yet</EmptyTitle>
              <EmptyDescription>Create routes and buses first, then schedule trips</EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <div className="space-y-1">
            {trips.map((t) => (
              <div key={t._id} className="flex items-center gap-3 p-3 rounded-xl hover:bg-muted/50">
                <CalendarIcon className="w-4 h-4 text-primary shrink-0" />
                <div className="flex-1 min-w-0">
                  <div className="font-medium text-sm">
                    {t.origin?.name ?? "?"} → {t.destination?.name ?? "?"}
                  </div>
                  <div className="text-xs text-muted-foreground">
                    {new Date(t.departureTime).toLocaleString()} — {t.priceAmount} {t.currency} — {t.seatsAvailable}/{t.totalSeats} seats
                  </div>
                </div>
                <span className={cn("text-[10px] font-semibold px-2 py-0.5 rounded-full", statusColors[t.status])}>
                  {t.status}
                </span>
                {t.status === "scheduled" && (
                  <Select
                    value={t.status}
                    onValueChange={(s) =>
                      updateStatus({ tripId: t._id, status: s })
                        .then(() => toast.success("Status updated"))
                        .catch(() => toast.error("Failed"))
                    }
                  >
                    <SelectTrigger className="w-28 h-7 text-xs">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="scheduled">Scheduled</SelectItem>
                      <SelectItem value="active">Active</SelectItem>
                      <SelectItem value="completed">Completed</SelectItem>
                      <SelectItem value="cancelled">Cancelled</SelectItem>
                    </SelectContent>
                  </Select>
                )}
                <Button variant="ghost" size="sm" className="cursor-pointer h-7 text-xs text-destructive" onClick={() => remove({ tripId: t._id }).then(() => toast.success("Trip deleted")).catch(() => toast.error("Failed"))}>
                  <Trash2Icon className="w-3 h-3" />
                </Button>
              </div>
            ))}
          </div>
        )}
      </CardContent>

      <Dialog open={showAdd} onOpenChange={setShowAdd}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Schedule Trip</DialogTitle>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <div className="space-y-1.5">
              <Label>Route *</Label>
              <Select value={routeId} onValueChange={setRouteId}>
                <SelectTrigger><SelectValue placeholder="Select route" /></SelectTrigger>
                <SelectContent>
                  {routes?.filter((r) => r.isActive).map((r) => (
                    <SelectItem key={r._id} value={r._id}>
                      {r.origin?.name} → {r.destination?.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Bus *</Label>
              <Select value={busId} onValueChange={setBusId}>
                <SelectTrigger><SelectValue placeholder="Select bus" /></SelectTrigger>
                <SelectContent>
                  {buses?.filter((b) => b.isActive).map((b) => (
                    <SelectItem key={b._id} value={b._id}>
                      {b.name} ({b.capacity} seats)
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Departure *</Label>
                <Input type="datetime-local" value={departure} onChange={(e) => setDeparture(e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label>Arrival *</Label>
                <Input type="datetime-local" value={arrival} onChange={(e) => setArrival(e.target.value)} />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Price *</Label>
                <Input type="number" value={price} onChange={(e) => setPrice(e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label>Currency</Label>
                <Select value={currency} onValueChange={setCurrency}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="XAF">XAF</SelectItem>
                    <SelectItem value="USD">USD</SelectItem>
                    <SelectItem value="EUR">EUR</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setShowAdd(false)} className="cursor-pointer">Cancel</Button>
            <Button onClick={handleAdd} disabled={loading || !routeId || !busId || !departure || !arrival} className="cursor-pointer">
              {loading ? "Scheduling..." : "Schedule Trip"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}

// ─── Tickets Tab ────────────────────────────────────────────────────────────

function TicketsTab({ companyId }: { companyId: Id<"companies"> }) {
  const trips = useQuery(api.adminManage.listTrips, { companyId });
  const bookings = useQuery(api.adminManage.listBookings, { companyId });
  const sell = useMutation(api.adminManage.sellTicket);
  const [showSell, setShowSell] = useState(false);
  const [tripId, setTripId] = useState("");
  const [passengerName, setPassengerName] = useState("");
  const [passengerPhone, setPassengerPhone] = useState("");
  const [selectedSeat, setSelectedSeat] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const scheduledTrips = trips?.filter((t) => t.status === "scheduled" && t.seatsAvailable > 0) ?? [];
  const selectedTrip = scheduledTrips.find((t) => t._id === tripId);

  // Fetch occupied seats for the selected trip
  const occupiedSeats = useQuery(
    api.bookings.getOccupiedSeats,
    tripId ? { tripId: tripId as Id<"trips"> } : "skip"
  );

  const handleSell = async () => {
    if (!tripId || !passengerName.trim()) return;
    setLoading(true);
    try {
      await sell({
        tripId: tripId as Id<"trips">,
        passengerName: passengerName.trim(),
        passengerPhone: passengerPhone.trim() || undefined,
        seatNumber: selectedSeat || undefined,
      });
      toast.success("Ticket sold!");
      setTripId("");
      setPassengerName("");
      setPassengerPhone("");
      setSelectedSeat(null);
      setShowSell(false);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Failed to sell ticket";
      toast.error(msg);
    } finally {
      setLoading(false);
    }
  };

  const statusColors: Record<string, string> = {
    confirmed: "bg-green-500/10 text-green-600",
    pending_payment: "bg-yellow-500/10 text-yellow-600",
    cancelled: "bg-red-500/10 text-red-600",
    collected: "bg-blue-500/10 text-blue-600",
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base">Ticket Sales</CardTitle>
          <Button size="sm" className="cursor-pointer" onClick={() => setShowSell(true)}>
            <TicketIcon className="w-4 h-4 mr-1" /> Sell Ticket
          </Button>
        </div>
      </CardHeader>
      <CardContent>
        {bookings === undefined ? (
          <div className="space-y-2">
            {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-14 w-full rounded-xl" />)}
          </div>
        ) : bookings.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon"><TicketIcon /></EmptyMedia>
              <EmptyTitle>No tickets sold yet</EmptyTitle>
              <EmptyDescription>Sell tickets for scheduled trips</EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <div className="space-y-1">
            {bookings.map((b) => (
              <div key={b._id} className="flex items-center gap-3 p-3 rounded-xl hover:bg-muted/50">
                <TicketIcon className="w-4 h-4 text-primary shrink-0" />
                <div className="flex-1 min-w-0">
                  <div className="font-medium text-sm">{b.passengerName} — {b.bookingReference}</div>
                  <div className="text-xs text-muted-foreground">
                    {b.origin?.name ?? "?"} → {b.destination?.name ?? "?"} — {b.totalPrice} {b.currency}
                    {b.seatNumber && <span className="ml-2 font-medium text-primary">Seat #{b.seatNumber}</span>}
                  </div>
                </div>
                <span className={cn("text-[10px] font-semibold px-2 py-0.5 rounded-full", statusColors[b.status] ?? "bg-muted text-muted-foreground")}>
                  {b.status}
                </span>
              </div>
            ))}
          </div>
        )}
      </CardContent>

      <Dialog open={showSell} onOpenChange={setShowSell}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Sell Ticket</DialogTitle>
            <DialogDescription>Sell a ticket for a scheduled trip</DialogDescription>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <div className="space-y-1.5">
              <Label>Trip *</Label>
              <Select value={tripId} onValueChange={(v) => { setTripId(v); setSelectedSeat(null); }}>
                <SelectTrigger><SelectValue placeholder="Select trip" /></SelectTrigger>
                <SelectContent>
                  {scheduledTrips.map((t) => (
                    <SelectItem key={t._id} value={t._id}>
                      {t.origin?.name} → {t.destination?.name} — {new Date(t.departureTime).toLocaleString()} ({t.seatsAvailable} seats)
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Passenger Name *</Label>
              <Input value={passengerName} onChange={(e) => setPassengerName(e.target.value)} placeholder="e.g. Jean Dupont" />
            </div>
            <div className="space-y-1.5">
              <Label>Phone (optional)</Label>
              <Input value={passengerPhone} onChange={(e) => setPassengerPhone(e.target.value)} placeholder="+237..." />
            </div>
            {/* Seat selection */}
            {selectedTrip && selectedTrip.totalSeats > 0 && (
              <div className="space-y-1.5">
                <Label>Seat</Label>
                <SeatPicker
                  totalSeats={selectedTrip.totalSeats}
                  occupiedSeats={occupiedSeats ?? []}
                  selectedSeat={selectedSeat}
                  onSelect={setSelectedSeat}
                  busType={selectedTrip.bus?.busType}
                />
              </div>
            )}
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setShowSell(false)} className="cursor-pointer">Cancel</Button>
            <Button onClick={handleSell} disabled={loading || !tripId || !passengerName.trim()} className="cursor-pointer">
              {loading ? "Selling..." : "Sell Ticket"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
