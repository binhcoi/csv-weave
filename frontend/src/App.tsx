import { Navigate, Route, Routes } from 'react-router'
import AppLayout from './AppLayout'
import FilesPage from './pages/FilesPage'
import FileTypesPage from './pages/FileTypesPage'
import HelpPage from './pages/HelpPage'
import MapsPage from './pages/MapsPage'
import NotFoundPage from './pages/NotFoundPage'

function App() {
  return (
    <Routes>
      <Route element={<AppLayout />}>
        <Route index element={<Navigate to="/help" replace />} />
        <Route path="help" element={<HelpPage />} />
        <Route path="file-types" element={<FileTypesPage />} />
        <Route path="maps" element={<MapsPage />} />
        <Route path="files" element={<FilesPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  )
}

export default App
