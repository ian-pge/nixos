import {
  Action,
  ActionPanel,
  Alert,
  Color,
  confirmAlert,
  getPreferenceValues,
  Icon,
  List,
  showToast,
  Toast,
} from "@vicinae/api";
import { useCallback, useEffect, useMemo, useState } from "react";

const API_BASE_URL = "https://rest.runpod.io/v1";
const REQUEST_TIMEOUT_MS = 20_000;

type PodStatus = "RUNNING" | "EXITED" | "TERMINATED";
type LocalTransition = "STARTING" | "STOPPING";

type Preferences = { apiKey: string; consoleUrl: string };

type RunPod = {
  id?: string;
  name?: string;
  desiredStatus?: PodStatus;
  adjustedCostPerHr?: number;
  costPerHr?: number | string;
  image?: string;
  interruptible?: boolean;
  lastStartedAt?: string;
  lastStatusChange?: string;
  locked?: boolean;
  memoryInGb?: number;
  vcpuCount?: number;
  volumeInGb?: number;
  volumeMountPath?: string;
  publicIp?: string | null;
  portMappings?: Record<string, number> | null;
  ports?: string[];
  gpu?: { count?: number; displayName?: string };
  machine?: { gpuDisplayName?: string; dataCenterId?: string; location?: string };
  networkVolume?: {
    id?: string;
    name?: string;
    size?: number;
    dataCenterId?: string;
  };
};

class RunPodApiError extends Error {
  constructor(message: string, readonly status?: number) {
    super(message);
    this.name = "RunPodApiError";
  }
}

function cleanApiKey(apiKey: string): string {
  return apiKey.trim().replace(/^Bearer\s+/i, "");
}

async function apiRequest<T>(apiKey: string, path: string, method = "GET"): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(`${API_BASE_URL}${path}`, {
      method,
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${cleanApiKey(apiKey)}`,
      },
      signal: controller.signal,
    });
    const body = await response.text();

    if (!response.ok) {
      let detail = body.trim();
      try {
        const parsed = JSON.parse(body) as { error?: string; message?: string };
        detail = parsed.message ?? parsed.error ?? detail;
      } catch {
        // RunPod does not define a stable error response schema.
      }
      throw new RunPodApiError(
        `RunPod API returned ${response.status}${detail ? `: ${detail}` : ""}`,
        response.status,
      );
    }

    return (body ? JSON.parse(body) : undefined) as T;
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      throw new RunPodApiError("The RunPod request timed out.");
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

const listPods = (apiKey: string) =>
  apiRequest<RunPod[]>(apiKey, "/pods?includeMachine=true&includeNetworkVolume=true");

const changeLifecycle = (apiKey: string, podId: string, action: "start" | "stop") =>
  apiRequest<void>(apiKey, `/pods/${encodeURIComponent(podId)}/${action}`, "POST");

function errorMessage(error: unknown): string {
  if (error instanceof RunPodApiError && error.status === 401) {
    return "Authentication failed. Check the RunPod API key in extension preferences.";
  }
  return error instanceof Error ? error.message : String(error);
}

function podName(pod: RunPod): string {
  return pod.name?.trim() || pod.id || "Unnamed Pod";
}

function hourlyCost(pod: RunPod): number | undefined {
  const value = pod.adjustedCostPerHr ?? pod.costPerHr;
  if (value === undefined) return undefined;
  const number = Number(value);
  return Number.isFinite(number) ? number : undefined;
}

function gpuLabel(pod: RunPod): string {
  const name = pod.gpu?.displayName ?? pod.machine?.gpuDisplayName ?? "GPU";
  const count = pod.gpu?.count;
  return count && count > 1 ? `${count}× ${name}` : name;
}

function sshCommand(pod: RunPod): string | undefined {
  if (!pod.publicIp) return undefined;
  const port = pod.portMappings?.["22"];
  return port ? `ssh root@${pod.publicIp} -p ${port}` : undefined;
}

function statusPresentation(
  pod: RunPod,
  transition?: LocalTransition,
): { text: string; color: Color; icon: Icon } {
  if (transition === "STARTING") return { text: "Starting…", color: Color.Yellow, icon: Icon.CircleProgress };
  if (transition === "STOPPING") return { text: "Stopping…", color: Color.Yellow, icon: Icon.CircleProgress };
  if (pod.desiredStatus === "RUNNING") return { text: "Running", color: Color.Green, icon: Icon.CircleFilled };
  if (pod.desiredStatus === "EXITED") return { text: "Stopped", color: Color.Orange, icon: Icon.StopFilled };
  if (pod.desiredStatus === "TERMINATED") return { text: "Terminated", color: Color.Red, icon: Icon.CircleDisabled };
  return { text: "Unknown", color: Color.SecondaryText, icon: Icon.QuestionMarkCircle };
}

function dateText(value?: string): string | undefined {
  if (!value) return undefined;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
}

function PodActions({
  pod,
  consoleUrl,
  transition,
  onLifecycle,
  onRefresh,
}: {
  pod: RunPod;
  consoleUrl: string;
  transition?: LocalTransition;
  onLifecycle: (pod: RunPod, action: "start" | "stop") => Promise<void>;
  onRefresh: () => Promise<void>;
}) {
  const id = pod.id;
  const ssh = sshCommand(pod);
  const cost = hourlyCost(pod);

  return (
    <ActionPanel>
      {id && pod.desiredStatus === "EXITED" && !transition ? (
        <Action
          title="Start / Resume Pod"
          icon={Icon.PlayFilled}
          onAction={() => onLifecycle(pod, "start")}
        />
      ) : null}
      {id && pod.desiredStatus === "RUNNING" && !pod.locked && !transition ? (
        <Action
          title="Stop Pod"
          icon={Icon.StopFilled}
          style={Action.Style.Destructive}
          onAction={() => onLifecycle(pod, "stop")}
        />
      ) : null}
      <Action.OpenInBrowser title="Open RunPod Console" url={consoleUrl} icon={Icon.Globe01} />
      {id ? <Action.CopyToClipboard title="Copy Pod ID" content={id} /> : null}
      {ssh ? (
        <Action.CopyToClipboard title="Copy SSH Command" content={ssh} icon={Icon.Terminal} />
      ) : null}
      <Action
        title="Refresh Pods"
        icon={Icon.ArrowClockwise}
        shortcut={{ modifiers: ["cmd"], key: "r" }}
        onAction={onRefresh}
      />
      {cost !== undefined ? (
        <Action.CopyToClipboard title="Copy Hourly Cost" content={`$${cost.toFixed(4)}/hr`} />
      ) : null}
    </ActionPanel>
  );
}

function PodItem({
  pod,
  consoleUrl,
  transition,
  onLifecycle,
  onRefresh,
}: {
  pod: RunPod;
  consoleUrl: string;
  transition?: LocalTransition;
  onLifecycle: (pod: RunPod, action: "start" | "stop") => Promise<void>;
  onRefresh: () => Promise<void>;
}) {
  const status = statusPresentation(pod, transition);
  const cost = hourlyCost(pod);
  const statusChanged = pod.lastStatusChange?.trim();

  return (
    <List.Item
      id={pod.id}
      title={podName(pod)}
      subtitle={pod.id}
      icon={{ source: status.icon, tintColor: status.color }}
      keywords={[pod.id ?? "", pod.image ?? "", gpuLabel(pod), pod.desiredStatus ?? ""]}
      accessories={[
        { tag: { value: status.text, color: status.color } },
        { text: gpuLabel(pod) },
        ...(cost === undefined ? [] : [{ text: `$${cost.toFixed(4)}/hr` }]),
        ...(pod.locked ? [{ icon: { source: Icon.Lock, tintColor: Color.Yellow }, tooltip: "Locked" }] : []),
      ]}
      detail={
        <List.Item.Detail
          markdown={statusChanged ? `## Last status change\n\n${statusChanged}` : undefined}
          metadata={
            <List.Item.Detail.Metadata>
              <List.Item.Detail.Metadata.TagList title="Status">
                <List.Item.Detail.Metadata.TagList.Item text={status.text} color={status.color} />
              </List.Item.Detail.Metadata.TagList>
              <List.Item.Detail.Metadata.Label title="Pod ID" text={pod.id ?? "Unknown"} />
              <List.Item.Detail.Metadata.Label title="GPU" text={gpuLabel(pod)} />
              {cost !== undefined ? (
                <List.Item.Detail.Metadata.Label title="Hourly cost" text={`$${cost.toFixed(4)}`} />
              ) : null}
              {pod.vcpuCount !== undefined ? (
                <List.Item.Detail.Metadata.Label title="vCPUs" text={String(pod.vcpuCount)} />
              ) : null}
              {pod.memoryInGb !== undefined ? (
                <List.Item.Detail.Metadata.Label title="Memory" text={`${pod.memoryInGb} GB`} />
              ) : null}
              {pod.image ? <List.Item.Detail.Metadata.Label title="Image" text={pod.image} /> : null}
              {pod.volumeInGb !== undefined ? (
                <List.Item.Detail.Metadata.Label
                  title="Volume"
                  text={`${pod.volumeInGb} GB${pod.volumeMountPath ? ` at ${pod.volumeMountPath}` : ""}`}
                />
              ) : null}
              {pod.networkVolume ? (
                <List.Item.Detail.Metadata.Label
                  title="Network volume"
                  text={`${pod.networkVolume.name ?? pod.networkVolume.id ?? "Attached"}${pod.networkVolume.size ? ` (${pod.networkVolume.size} GB)` : ""}`}
                />
              ) : null}
              {pod.publicIp ? <List.Item.Detail.Metadata.Label title="Public IP" text={pod.publicIp} /> : null}
              {dateText(pod.lastStartedAt) ? (
                <List.Item.Detail.Metadata.Label title="Last started" text={dateText(pod.lastStartedAt)!} />
              ) : null}
            </List.Item.Detail.Metadata>
          }
        />
      }
      actions={
        <PodActions
          pod={pod}
          consoleUrl={consoleUrl}
          transition={transition}
          onLifecycle={onLifecycle}
          onRefresh={onRefresh}
        />
      }
    />
  );
}

export default function ManagePods() {
  const preferences = getPreferenceValues<Preferences>();
  const [pods, setPods] = useState<RunPod[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string>();
  const [transitions, setTransitions] = useState<Record<string, LocalTransition>>({});

  const refresh = useCallback(async () => {
    setIsLoading(true);
    try {
      setPods(await listPods(preferences.apiKey));
      setError(undefined);
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setIsLoading(false);
    }
  }, [preferences.apiKey]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const lifecycle = useCallback(
    async (pod: RunPod, action: "start" | "stop") => {
      if (!pod.id) return;
      const starting = action === "start";
      const cost = hourlyCost(pod);
      const confirmed = await confirmAlert({
        title: `${starting ? "Start" : "Stop"} ${podName(pod)}?`,
        message: starting
          ? `This resumes billing${cost === undefined ? "" : ` at about $${cost.toFixed(4)}/hr`}.`
          : "This releases the GPU. Data outside the persistent volume may be lost.",
        primaryAction: {
          title: starting ? "Start Pod" : "Stop Pod",
          style: starting ? Alert.ActionStyle.Default : Alert.ActionStyle.Destructive,
        },
      });
      if (!confirmed) return;

      setTransitions((current) => ({ ...current, [pod.id!]: starting ? "STARTING" : "STOPPING" }));
      const toast = await showToast({
        style: Toast.Style.Animated,
        title: `${starting ? "Starting" : "Stopping"} ${podName(pod)}…`,
      });
      try {
        await changeLifecycle(preferences.apiKey, pod.id, action);
        toast.style = Toast.Style.Success;
        toast.title = `${podName(pod)} ${starting ? "is starting" : "was stopped"}`;
        await refresh();
      } catch (caught) {
        toast.style = Toast.Style.Failure;
        toast.title = `Could not ${action} ${podName(pod)}`;
        toast.message = errorMessage(caught);
      } finally {
        setTransitions((current) => {
          const next = { ...current };
          delete next[pod.id!];
          return next;
        });
      }
    },
    [preferences.apiKey, refresh],
  );

  const groups = useMemo(
    () => ({
      running: pods.filter((pod) => pod.desiredStatus === "RUNNING"),
      stopped: pods.filter((pod) => pod.desiredStatus === "EXITED"),
      terminated: pods.filter((pod) => pod.desiredStatus === "TERMINATED"),
      unknown: pods.filter((pod) => !pod.desiredStatus),
    }),
    [pods],
  );

  const item = (pod: RunPod) => (
    <PodItem
      key={pod.id ?? podName(pod)}
      pod={pod}
      consoleUrl={preferences.consoleUrl}
      transition={pod.id ? transitions[pod.id] : undefined}
      onLifecycle={lifecycle}
      onRefresh={refresh}
    />
  );

  return (
    <List isLoading={isLoading} isShowingDetail searchBarPlaceholder="Search RunPod Pods…">
      {error && !isLoading ? (
        <List.EmptyView
          title="Could not load RunPod Pods"
          description={error}
          icon={Icon.Exclamationmark}
          actions={
            <ActionPanel>
              <Action title="Try Again" icon={Icon.ArrowClockwise} onAction={refresh} />
              <Action.OpenInBrowser title="Open RunPod Console" url={preferences.consoleUrl} />
            </ActionPanel>
          }
        />
      ) : null}
      {!error && !isLoading && pods.length === 0 ? (
        <List.EmptyView
          title="No RunPod Pods"
          description="Create a Pod in the RunPod Console, then refresh this list."
          icon={Icon.Cloud}
          actions={
            <ActionPanel>
              <Action.OpenInBrowser title="Open RunPod Console" url={preferences.consoleUrl} />
              <Action title="Refresh Pods" icon={Icon.ArrowClockwise} onAction={refresh} />
            </ActionPanel>
          }
        />
      ) : null}
      {groups.running.length ? (
        <List.Section title={`Running Pods (${groups.running.length})`}>{groups.running.map(item)}</List.Section>
      ) : null}
      {groups.stopped.length ? (
        <List.Section title={`Stopped Pods (${groups.stopped.length})`}>{groups.stopped.map(item)}</List.Section>
      ) : null}
      {groups.terminated.length ? (
        <List.Section title={`Terminated Pods (${groups.terminated.length})`}>
          {groups.terminated.map(item)}
        </List.Section>
      ) : null}
      {groups.unknown.length ? (
        <List.Section title={`Unknown Status (${groups.unknown.length})`}>{groups.unknown.map(item)}</List.Section>
      ) : null}
    </List>
  );
}
