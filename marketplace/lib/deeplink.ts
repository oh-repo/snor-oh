export type PkgFormat = "snoroh" | "animime";

export function buildInstallUrl(format: PkgFormat, id: string): string {
  return `${format}://install?id=${encodeURIComponent(id)}&v=1`;
}

export const DOWNLOAD_URL: Record<PkgFormat, string> = {
  animime: "https://github.com/vietnguyenhoangw/ani-mime/releases/latest",
  snoroh: "https://github.com/thanh-dong/snor-oh/releases/latest",
};
