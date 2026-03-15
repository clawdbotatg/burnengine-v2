import "@rainbow-me/rainbowkit/styles.css";
import "@scaffold-ui/components/styles.css";
import { ScaffoldEthAppWithProviders } from "~~/components/ScaffoldEthAppWithProviders";
import { ThemeProvider } from "~~/components/ThemeProvider";
import "~~/styles/globals.css";
import { getMetadata } from "~~/utils/scaffold-eth/getMetadata";

export const metadata = getMetadata({
  title: "BurnEngine V2",
  description: "Permissionless ₸USD Burn Hyperstructure",
  imageRelativePath: "/thumbnail.png",
});

// Override OG image with absolute URL
metadata.openGraph = {
  ...metadata.openGraph,
  images: ["https://burnengine.eth.limo/thumbnail.png"],
};
metadata.twitter = {
  ...metadata.twitter,
  images: ["https://burnengine.eth.limo/thumbnail.png"],
};
metadata.icons = { icon: [{ url: "/favicon.ico" }] };

const ScaffoldEthApp = ({ children }: { children: React.ReactNode }) => {
  return (
    <html suppressHydrationWarning className={``}>
      <body>
        <ThemeProvider enableSystem>
          <ScaffoldEthAppWithProviders>{children}</ScaffoldEthAppWithProviders>
        </ThemeProvider>
      </body>
    </html>
  );
};

export default ScaffoldEthApp;
